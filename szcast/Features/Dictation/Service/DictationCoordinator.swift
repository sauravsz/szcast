import AppKit
import AVFoundation

@MainActor
@Observable
final class DictationCoordinator {
    private enum Phase { case idle, starting, listening, transcribing, stopping }

    private let settings: AppSettings
    private let hotKeys: HotKeyManager
    let models: DictationModelStore
    let dictionaryStore = DictationDictionaryStore()
    let historyStore = DictationHistoryStore()
    let s1Downloader = DictationS1Downloader()
    private let s1Polisher = DictationS1Polisher()
    private(set) var lastDictation: String?
    private let capture = DictationCapture()
    private let audioDucker: DictationAudioDucker
    private let cues = DictationCueRunner()
    private let panel = DictationPanelController()
    private let injector: TextInjector
    private let showMessage: (String, DialogTone) -> Void
    private let confirmEnable: () async -> Bool
    @ObservationIgnored private var phase: Phase = .idle
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var enableTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var liveOffset = 0
    @ObservationIgnored private var liveText = ""
    @ObservationIgnored private var liveDeliveryFailed = false
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var cueTask: Task<Void, Never>?
    @ObservationIgnored private var pendingStartCue: UUID?
    @ObservationIgnored private var finishWhenStarted = false
    @ObservationIgnored private var target: InjectionTarget?
    /// The field a mic button is dictating into; nil for a shortcut's session.
    private(set) var field: DictationField?

    init(
        settings: AppSettings, hotKeys: HotKeyManager, models: DictationModelStore,
        injector: TextInjector, audioDucker: DictationAudioDucker,
        confirmEnable: @escaping () async -> Bool,
        showMessage: @escaping (String, DialogTone) -> Void
    ) {
        self.settings = settings
        self.hotKeys = hotKeys
        self.models = models
        self.injector = injector
        self.audioDucker = audioDucker
        self.confirmEnable = confirmEnable
        self.showMessage = showMessage
        panel.onAccept = { [weak self] in self?.accept() }
        panel.onCancel = { [weak self] in self?.cancel() }
        capture.onLevels = { [weak self] in
            guard let self else { return }
            panel.state.levels = $0
            if pendingStartCue == token { playStartCue() }
        }
        capture.onLimit = { [weak self] in self?.accept() }
        self.lastDictation = historyStore.items.first?.text
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.dictationEnabled else { return }
        guard enabled else {
            settings.dictationEnabled = false
            enableTask?.cancel()
            cancel()
            return
        }
        guard enableTask == nil else { return }
        NSApp.activate()
        enableTask = Task { [weak self] in
            guard let self else { return }
            defer { enableTask = nil }
            guard await confirmEnable(), !Task.isCancelled else { return }
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled else { return }
            guard granted else {
                showMessage(
                    String(localized: "Allow szcast to use the microphone in System Settings"), .danger)
                return
            }
            settings.dictationEnabled = true
            if settings.dictationDestination.pastes { Permissions.ensureAccessibility() }
        }
    }

    func downloadModel(_ model: DictationModel) async {
        do { try await models.download(model) } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch { showMessage(error.localizedDescription, .danger) }
    }

    func removeModel(_ model: DictationModel) async {
        do { try await models.delete(model) } catch { showMessage(error.localizedDescription, .danger) }
    }

    var holdShortcutIssue: String? {
        guard let binding = hotKeys.binding(for: .dictation) else { return nil }
        guard binding.shortcut != nil || binding.holdKey != nil else {
            return String(localized: "Record a single modifier or a key combination for hold to talk.")
        }
        if let owner = hotKeys.conflictOwner(of: binding, excluding: .dictation) {
            return String(localized: "This shortcut is also used by \(owner). Record another shortcut.")
        }
        return nil
    }

    func pressed() {
        guard settings.dictationEnabled else { return }
        if phase == .stopping { return }
        if settings.dictationMode == .pushToTalk,
            hotKeys.binding(for: .dictation)?.shortcut == nil,
            hotKeys.binding(for: .dictation)?.holdKey == nil
        {
            showMessage(
                String(localized: "Hold to talk needs a key combination or a single modifier"), .danger)
            return
        }
        if phase != .idle {
            if settings.dictationMode == .toggle { finish() }
            return
        }
        begin(target: InjectionTarget.current())
    }

    var isEnabled: Bool { settings.dictationEnabled }
    var hasModel: Bool { models.isInstalled(settings.dictationModel) }

    /// A field's own mic: click to start and click to finish, whatever the shortcut's mode or focus.
    func toggle(into editor: any InjectableTextView) {
        guard settings.dictationEnabled, phase != .stopping else { return }
        guard phase == .idle else {
            if field?.editor == ObjectIdentifier(editor) { finish() }
            return
        }
        field = DictationField(editor: ObjectIdentifier(editor))
        begin(target: .ownEditor(editor))
    }

    private func finish() {
        if phase == .starting {
            finishWhenStarted = true
        } else {
            accept()
        }
    }

    func prewarm() {
        guard settings.dictationEnabled else { return }
        models.prewarm(settings.dictationModel)
        if settings.dictationS1Enabled {
            DictationLlamaServerManager.shared.prewarm(idleRelease: settings.dictationS1IdleRelease)
        }
    }

    private func begin(target: InjectionTarget?) {
        guard models.isInstalled(settings.dictationModel) else {
            field = nil
            showMessage(String(localized: "Download the dictation model in Settings first"), .danger)
            return
        }
        models.prewarm(settings.dictationModel)
        if settings.dictationS1Enabled {
            DictationLlamaServerManager.shared.prewarm(idleRelease: settings.dictationS1IdleRelease)
        }
        token = UUID()
        let current = token
        phase = .starting
        finishWhenStarted = false
        liveOffset = 0
        liveText = ""
        self.target = target
        pendingStartCue = settings.dictationPlaysSounds ? current : nil
        if pendingStartCue == nil { audioDucker.begin(mode: settings.dictationOtherAudioMode) }
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await capture.start(microphoneID: settings.dictationMicrophone)
                guard token == current, settings.dictationEnabled else {
                    _ = await capture.stop()
                    return
                }
                phase = .listening
                panel.show()
                startLiveInsertion(token: current)
                if finishWhenStarted { accept() }
            } catch {
                guard token == current else { return }
                reset()
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    /// A Bluetooth headset's output resumes up to a quarter second after the first samples.
    private static let bluetoothSettle = Duration.milliseconds(500)

    private func playStartCue() {
        pendingStartCue = nil
        let current = token
        cueTask = Task { [weak self] in
            guard let self else { return }
            if capture.isBluetooth { try? await Task.sleep(for: Self.bluetoothSettle) }
            guard token == current, phase == .starting || phase == .listening else { return }
            cues.play(.start)
            audioDucker.begin(mode: settings.dictationOtherAudioMode)
        }
    }

    func released() {
        guard settings.dictationMode == .pushToTalk else { return }
        if phase == .starting { finishWhenStarted = true }
        if phase == .listening { accept() }
    }

    func accept() {
        guard phase == .listening else { return }
        phase = .transcribing
        panel.state.phase = .transcribing
        field?.isTranscribing = true
        if settings.dictationPlaysSounds {
            audioDucker.restoreImmediately()
            cues.play(.stop)
        } else {
            audioDucker.end(mode: settings.dictationOtherAudioMode)
        }
        // A cancelled chunk keeps its audio: the final pass starts at liveOffset, losing nothing.
        let pendingLive = liveTask
        liveTask = nil
        pendingLive?.cancel()
        let current = token
        let model = settings.dictationModel
        let language = settings.dictationLanguage
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            await pendingLive?.value
            let samples = await capture.stop()
            // Queued chunks land first: reset would drop them, and the remainder spaces after them.
            if !liveText.isEmpty { await injector.drain() }
            guard token == current else { return }
            let tail = liveOffset < samples.count ? Array(samples[liveOffset...]) : []
            let destination = field == nil ? settings.dictationDestination : .paste
            if tail.count < 1_600 {
                if liveText.isEmpty {
                    reset(cancelTranscription: false)
                    showMessage(String(localized: "No speech was recorded"), .danger)
                } else {
                    finishWithoutRemainder(destination)
                }
                return
            }
            do {
                let transcript = try await models.transcribe(
                    tail, model: model,
                    language: language)
                guard token == current else { return }

                var processed = transcript
                if settings.dictationConvertSpokenEmoji {
                    processed = DictationTextFormatter.convertSpokenEmoji(processed)
                }
                if settings.dictationSpokenPunctuation {
                    processed = DictationTextFormatter.convertSpokenPunctuation(processed)
                }
                if settings.dictationRemoveFillerWords {
                    processed = DictationTextFormatter.removeFillerWords(processed)
                }
                processed = dictionaryStore.applyDictionaryAndPacks(processed)
                processed = dictionaryStore.applySnippets(processed)

                if settings.dictationS1Enabled {
                    let s1 = DictationS1Settings(
                        enabled: true,
                        tone: settings.dictationS1Tone,
                        structure: settings.dictationS1Structure,
                        context: settings.dictationS1Context,
                        idleRelease: settings.dictationS1IdleRelease
                    )
                    processed = await s1Polisher.polish(processed, settings: s1)
                }

                // A mic belongs to its field: the text goes in there, never to the clipboard.
                let context = destination.pastes ? insertionContext() : nil
                let text = DictationTextFormatter.format(
                    processed, context: context,
                    adaptCapitalization: settings.dictationAdaptsCapitalization)
                let target = self.target
                let assembled = liveText + text
                guard !text.isEmpty else { finishWithoutRemainder(destination); return }

                lastDictation = assembled
                historyStore.add(text: assembled, rawText: transcript, duration: Double(tail.count) / 16000.0)

                panel.close()
                if destination.pastes {
                    injector.deliver(
                        InjectedText(text), target: target, expectedKeyword: nil,
                        keywordLength: 0, automaticGeneration: nil,
                        isValid: { [weak self] in self?.token == current },
                        onDelivered: { [weak self] in
                            guard let self, token == current else { return }
                            let lost = liveDeliveryFailed
                            if destination.copies || settings.dictationAutoCopyToClipboard {
                                Paster.copyPlainText(assembled)
                            }
                            reset(cancelTranscription: false)
                            if lost, destination.pastes {
                                showMessage(
                                    String(localized: "Couldn't paste some dictation into this app"),
                                    .danger)
                            }
                        },
                        onFailed: { [weak self] in
                            guard let self, token == current else { return }
                            reset(cancelTranscription: false)
                            if destination.copies || settings.dictationAutoCopyToClipboard {
                                Paster.copyPlainText(assembled)
                            }
                            showMessage(String(localized: "Couldn't paste dictation into this app"), .danger)
                        })
                } else {
                    Paster.copyPlainText(text)
                    reset(cancelTranscription: false)
                }
            } catch {
                guard token == current else { return }
                reset(cancelTranscription: false)
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    private func finishWithoutRemainder(_ destination: DictationDestination) {
        let text = liveText
        let lost = liveDeliveryFailed
        reset(cancelTranscription: false)
        if !text.isEmpty, destination.copies { Paster.copyPlainText(text) }
        if lost, destination.pastes {
            showMessage(String(localized: "Couldn't paste some dictation into this app"), .danger)
        }
    }

    /// Chunks already pasted only make sense where text is pasted at all.
    private var insertionPastes: Bool {
        field == nil ? settings.dictationDestination.pastes : true
    }

    /// Chunk spacing from the caret, else from pasted text, so chunks never glue without a space.
    private func insertionContext() -> DictationTextFormatter.Context? {
        if let context = DictationInsertionContext.read(in: target) { return context }
        guard !liveText.isEmpty else { return nil }
        return DictationTextFormatter.Context(before: liveText.suffix(512), after: Substring())
    }

    private func startLiveInsertion(token current: UUID) {
        guard insertionPastes, settings.dictationLiveInsertion else { return }
        liveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, token == current, phase == .listening else { return }
                guard settings.dictationLiveInsertion else { return }
                await flushLiveChunk(token: current)
            }
        }
    }

    private func flushLiveChunk(token current: UUID) async {
        let snapshot = capture.snapshot()
        guard token == current else { return }
        let fresh = snapshot.count - liveOffset
        guard fresh >= DictationAudioChunks.minimumLiveSamples else { return }
        guard
            fresh >= DictationAudioChunks.maximumLiveSamples
                || DictationAudioChunks.endsInPause(in: snapshot, from: liveOffset, to: snapshot.count)
        else { return }
        let end = DictationAudioChunks.liveCut(in: snapshot, from: liveOffset, to: snapshot.count)
        guard end > liveOffset else { return }
        let overlap = DictationAudioChunks.liveOverlapStart(in: snapshot, before: liveOffset)
        let segment = Array(snapshot[overlap..<end])
        do {
            let transcript = try await models.transcribe(
                segment, model: settings.dictationModel,
                language: settings.dictationLanguage)
            guard token == current else { return }
            liveOffset = end
            let context = insertionContext()
            let text = DictationTextFormatter.format(
                transcript, context: context,
                adaptCapitalization: settings.dictationAdaptsCapitalization)
            let stripped = DictationTextFormatter.stripEcho(text, after: liveText)
            guard !stripped.isEmpty else { return }
            liveText += stripped
            let target = self.target
            injector.deliver(
                InjectedText(stripped), target: target, expectedKeyword: nil,
                keywordLength: 0, automaticGeneration: nil,
                isValid: { [weak self] in self?.token == current },
                onDelivered: {},
                onFailed: { [weak self] in
                    guard let self, token == current else { return }
                    liveDeliveryFailed = true
                })
        } catch {
            // The final pass starts at liveOffset, so it covers what this chunk left behind.
        }
    }

    func cancel(in editor: any InjectableTextView) {
        guard let target = target?.ownEditor, target === editor else { return }
        cancel()
    }

    func cancel() {
        guard phase != .stopping, phase != .idle || !settings.dictationEnabled else { return }
        let pendingStart = startTask
        let pendingTranscription = transcriptionTask
        let pendingLive = liveTask
        reset()
        phase = .stopping
        let current = token
        stopTask = Task { [weak self] in
            guard let self else { return }
            await pendingStart?.value
            _ = await capture.stop()
            await pendingTranscription?.value
            await pendingLive?.value
            if !settings.dictationEnabled { await models.stop() }
            if token == current { phase = .idle; stopTask = nil }
        }
    }

    func prepareForTermination() {
        enableTask?.cancel()
        cancel()
        cueTask?.cancel()
        audioDucker.restoreImmediately()
        models.prepareForTermination()
        s1Downloader.cancelDownload()
        DictationLlamaServerManager.shared.stop()
    }

    private func reset(cancelTranscription: Bool = true) {
        token = UUID()
        if cancelTranscription { transcriptionTask?.cancel() }
        liveTask?.cancel()
        liveTask = nil
        liveOffset = 0
        liveText = ""
        liveDeliveryFailed = false
        startTask = nil
        transcriptionTask = nil
        phase = .idle
        target = nil
        field = nil
        panel.close()
        audioDucker.end(mode: settings.dictationOtherAudioMode)
    }

    func pasteLastDictation() {
        guard let last = lastDictation, !last.isEmpty else {
            showMessage(String(localized: "No recent dictation to paste"), .neutral)
            return
        }
        let activeTarget = InjectionTarget.current()
        injector.deliver(
            InjectedText(last), target: activeTarget, expectedKeyword: nil,
            keywordLength: 0, automaticGeneration: nil,
            isValid: { true },
            onDelivered: {},
            onFailed: { [weak self] in
                Paster.copyPlainText(last)
                self?.showMessage(String(localized: "Pasting failed; copied last dictation to clipboard"), .neutral)
            }
        )
    }

    func pasteHistoryItem(_ text: String) {
        lastDictation = text
        pasteLastDictation()
    }

    func copyLastDictation() {
        guard let last = lastDictation, !last.isEmpty else {
            showMessage(String(localized: "No recent dictation to copy"), .neutral)
            return
        }
        Paster.copyPlainText(last)
        showMessage(String(localized: "Copied last dictation to clipboard"), .success)
    }

    func addSelectedWordToDictionary() {
        let pb = NSPasteboard.general
        let initialChangeCount = pb.changeCount
        // Send Cmd+C key event
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }
            guard pb.changeCount != initialChangeCount,
                  let word = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !word.isEmpty else {
                self.showMessage(String(localized: "Select a word to add to Dictionary"), .neutral)
                return
            }
            self.dictionaryStore.addWord(canonical: word)
            self.showMessage(String(localized: "Added \"\(word)\" to Dictionary"), .success)
        }
    }
}

/// Which editor a mic session belongs to, so only that field's button shows it running.
struct DictationField: Equatable {
    let editor: ObjectIdentifier
    var isTranscribing = false
}
