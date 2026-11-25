import AppKit
import AVFoundation
import UniformTypeIdentifiers

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
    private let groqAudio = GroqAudioService()
    private let groqPolish = GroqPolishService()
    private let livePreviewCoordinator = DictationLivePreviewCoordinator()
    let transformStore = DictationTransformStore()
    private(set) var lastDictation: String?
    private(set) var isHandsFreeLocked = false
    private(set) var commandModeSelectedText: String?
    @ObservationIgnored private var lastPressTime: Date = .distantPast
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
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var cueTask: Task<Void, Never>?
    @ObservationIgnored private var pendingStartCue: UUID?
    @ObservationIgnored private var finishWhenStarted = false
    @ObservationIgnored private var rawModeSession = false
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
        capture.onAutoStopSilence = { [weak self] in self?.accept() }
        capture.onSilenceWarning = { [weak self] silent in
            self?.panel.state.isMicSilent = silent
        }
        capture.onClamshellWarning = { [weak self] muffled in
            self?.panel.state.isClamshellMuffled = muffled
        }
        capture.onSamples = { [weak self] samples in
            self?.livePreviewCoordinator.feed(samples)
        }
        livePreviewCoordinator.onPreviewText = { [weak self] preview in
            Task { @MainActor [weak self] in
                guard let self, phase == .listening else { return }
                panel.updatePreviewText(preview)
            }
        }
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
            if settings.dictationLivePreviewEnabled {
                livePreviewCoordinator.prewarm(
                    locale: DictationLanguage.previewLocale(for: settings.dictationLanguage))
            }
            if settings.dictationS1Enabled {
                DictationLlamaServerManager.shared.prewarm(idleRelease: settings.dictationS1IdleRelease)
            }
        }
    }

    func downloadModel(_ model: DictationModel) async {
        do {
            try await models.download(model)
            if settings.dictationEnabled, settings.dictationModel == model {
                models.ensurePrewarmed(model)
            }
        } catch is CancellationError {
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
        pressed(rawMode: false)
    }

    func pressedSecondary() {
        pressed(rawMode: true)
    }

    private func pressed(rawMode: Bool) {
        guard settings.dictationEnabled else { return }
        if phase == .stopping { return }
        if settings.dictationMode == .pushToTalk,
            !rawMode,
            hotKeys.binding(for: .dictation)?.shortcut == nil,
            hotKeys.binding(for: .dictation)?.holdKey == nil
        {
            showMessage(
                String(localized: "Hold to talk needs a key combination or a single modifier"), .danger)
            return
        }

        let now = Date()
        let interval = now.timeIntervalSince(lastPressTime)
        lastPressTime = now

        // Rapid double tap triggers hands-free lock
        if settings.dictationDoubleTapToLock && interval < 0.45 {
            isHandsFreeLocked = true
            panel.state.isLockedHandsFree = true
        }

        if phase != .idle {
            if isHandsFreeLocked || settings.dictationMode == .toggle || rawMode {
                isHandsFreeLocked = false
                panel.state.isLockedHandsFree = false
                finish()
            }
            return
        }
        rawModeSession = rawMode
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
        models.ensurePrewarmed(settings.dictationModel)
        if settings.dictationLivePreviewEnabled {
            livePreviewCoordinator.prewarm(
                locale: DictationLanguage.previewLocale(for: settings.dictationLanguage))
        }
        if settings.dictationS1Enabled {
            DictationLlamaServerManager.shared.startDaemon(idleRelease: settings.dictationS1IdleRelease)
        }
    }

    private func begin(target: InjectionTarget?) {
        if settings.dictationTranscriptionProvider == .parakeet {
            guard models.isInstalled(settings.dictationModel) else {
                field = nil
                showMessage(String(localized: "Download the dictation model in Settings first"), .danger)
                return
            }
            models.prewarm(settings.dictationModel)
        } else {
            guard !settings.groqAPIKey.isEmpty else {
                field = nil
                showMessage(String(localized: "Set your Groq API key in Dictation Settings first"), .danger)
                return
            }
        }
        if settings.dictationS1Enabled && settings.dictationPolishProvider == .localS1 {
            DictationLlamaServerManager.shared.startDaemon(idleRelease: settings.dictationS1IdleRelease)
        }
        token = UUID()
        let current = token
        phase = .starting
        finishWhenStarted = false
        self.target = target
        if settings.dictationCommandModeEnabled,
           let sel = DictationInsertionContext.readSelectedText(in: target),
           !sel.isEmpty {
            self.commandModeSelectedText = sel
            panel.state.commandModeText = sel
        } else {
            self.commandModeSelectedText = nil
            panel.state.commandModeText = nil
        }
        panel.state.isWhisperMode = settings.dictationWhisperMode
        panel.state.isLockedHandsFree = isHandsFreeLocked
        panel.state.isRawMode = rawModeSession
        panel.state.isMuted = false
        panel.state.onToggleMute = { [weak self] in
            guard let self else { return }
            let next = !capture.isMuted
            capture.setMuted(next)
            panel.state.isMuted = next
        }
        pendingStartCue = settings.dictationPlaysSounds ? current : nil
        if pendingStartCue == nil { audioDucker.begin(mode: settings.dictationOtherAudioMode) }
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await capture.start(
                    microphoneID: settings.dictationMicrophone,
                    whisperMode: settings.dictationWhisperMode,
                    allowLongCapture: isHandsFreeLocked || rawModeSession,
                    startMuted: false,
                    autoStopSilenceSeconds: settings.dictationAutoStopSilenceSeconds
                )
                guard token == current, settings.dictationEnabled else {
                    _ = await capture.stop()
                    return
                }
                phase = .listening
                panel.show()
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                if settings.dictationLivePreviewEnabled {
                    livePreviewCoordinator.start(
                        locale: DictationLanguage.previewLocale(for: settings.dictationLanguage))
                }
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
        if isHandsFreeLocked { return }
        if phase == .starting { finishWhenStarted = true }
        if phase == .listening { accept() }
    }

    func accept() {
        guard phase == .listening else { return }
        phase = .transcribing
        panel.state.phase = .transcribing
        panel.updatePreviewText("")
        livePreviewCoordinator.stop()
        field?.isTranscribing = true
        if settings.dictationPlaysSounds {
            audioDucker.restoreImmediately()
            cues.play(.stop)
        } else {
            audioDucker.end(mode: settings.dictationOtherAudioMode)
        }

        let current = token
        var model = settings.dictationModel
        let language = settings.dictationLanguage
        if settings.dictationHindiMode == .whisperApex, models.isInstalled(.whisperApex) {
            model = .whisperApex
        } else if settings.dictationBengaliMode == .indicFlex, models.isInstalled(.indicFlex) {
            model = .indicFlex
        }
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            let samples = await capture.stop()
            guard token == current else { return }
            let destination = field == nil ? settings.dictationDestination : .paste
            if samples.count < 1_600 {
                reset(cancelTranscription: false)
                if settings.dictationMode != .pushToTalk {
                    showMessage(String(localized: "No speech was recorded"), .danger)
                }
                return
            }
            do {
                var timed = TimedTranscript(text: "")
                if settings.dictationTranscriptionProvider == .groq {
                    guard !settings.groqAPIKey.isEmpty else {
                        throw GroqAudioService.GroqAudioError.missingAPIKey
                    }
                    let text = try await groqAudio.transcribe(
                        samples: samples,
                        apiKey: settings.groqAPIKey,
                        model: settings.dictationGroqTranscriptionModel,
                        language: language
                    )
                    timed = TimedTranscript(text: text)
                } else {
                    timed = try await models.transcribeTimed(
                        samples,
                        model: model,
                        language: language,
                        useVAD: settings.dictationVADEnabled
                    )
                }
                let transcript = timed.text
                guard token == current else { return }

                var processed = transcript
                processed = DictationTextFormatter.resolveBacktracks(processed)
                processed = DictationTextFormatter.collapseRepetitions(processed)
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

                let frontApp = target?.externalApp ?? NSWorkspace.shared.frontmostApplication
                let bundleID = frontApp?.bundleIdentifier

                if settings.dictationLivePreviewEnabled {
                    livePreviewCoordinator.prewarm(
                        locale: DictationLanguage.previewLocale(for: settings.dictationLanguage))
                }

                var s1 = DictationS1Settings(
                    enabled: true,
                    tone: settings.dictationS1Tone,
                    structure: settings.dictationS1Structure,
                    context: settings.dictationS1Context,
                    idleRelease: settings.dictationS1IdleRelease,
                    bengaliMode: settings.dictationBengaliMode,
                    hindiMode: settings.dictationHindiMode
                )
                if settings.dictationAutoAppRouting {
                    s1 = AppStyleRouter.resolvedS1Settings(base: s1, bundleID: bundleID)
                }

                if let selectedText = self.commandModeSelectedText, !selectedText.isEmpty {
                    // Command Mode: Rewrites highlighted text using voice instruction
                    if settings.dictationPolishProvider == .groq, !settings.groqAPIKey.isEmpty {
                        do {
                            processed = try await groqPolish.transform(
                                text: selectedText,
                                instruction: processed,
                                apiKey: settings.groqAPIKey,
                                model: settings.dictationGroqPolishModel
                            )
                        } catch {
                            processed = await s1Polisher.transform(text: selectedText, instruction: processed, settings: s1)
                        }
                    } else {
                        processed = await s1Polisher.transform(text: selectedText, instruction: processed, settings: s1)
                    }
                } else if settings.dictationAutoApplyTransform,
                          let transform = transformStore.transform(with: settings.dictationActiveTransformID) {
                    // Custom Transform applied to dictation
                    if settings.dictationPolishProvider == .groq, !settings.groqAPIKey.isEmpty {
                        do {
                            processed = try await groqPolish.transform(
                                text: processed,
                                instruction: transform.systemPrompt,
                                apiKey: settings.groqAPIKey,
                                model: settings.dictationGroqPolishModel
                            )
                        } catch {
                            processed = await s1Polisher.transform(text: processed, instruction: transform.systemPrompt, settings: s1)
                        }
                    } else {
                        processed = await s1Polisher.transform(text: processed, instruction: transform.systemPrompt, settings: s1)
                    }
                } else if settings.dictationS1Enabled, !rawModeSession {
                    let polishProvider: DictationPolishProvider =
                        (settings.dictationPolishProvider == .groq && !settings.groqAPIKey.isEmpty) ? .groq : .localS1
                    processed = await TranscriptAIService.polishLongTranscript(
                        processed,
                        provider: polishProvider,
                        s1Settings: s1,
                        groqAPIKey: settings.groqAPIKey,
                        groqModel: settings.dictationGroqPolishModel,
                        polisher: s1Polisher,
                        groq: groqPolish
                    )
                    // Authoritative post-pass: ensure user custom words, vocabulary packs, and snippets
                    // are never undone or mis-cased by the speech normalization model
                    processed = dictionaryStore.applyDictionaryAndPacks(processed)
                    processed = dictionaryStore.applySnippets(processed)
                }

                if settings.dictationBengaliMode == .avroPhonetic {
                    processed = AvroPhoneticConverter.convert(processed)
                }
                if settings.dictationHindiMode == .phoneticEngine {
                    processed = HinglishPhoneticConverter.convert(processed)
                }

                // A mic belongs to its field: the text goes in there, never to the clipboard.
                let context = destination.pastes ? insertionContext() : nil
                var text = DictationTextFormatter.format(
                    processed, context: context,
                    adaptCapitalization: settings.dictationAdaptsCapitalization)
                if settings.dictationAutoAppRouting {
                    text = AppStyleRouter.applyCategoryFormatting(text, bundleID: bundleID)
                }
                let target = self.target
                guard !text.isEmpty else {
                    reset(cancelTranscription: false)
                    return
                }

                lastDictation = text
                historyStore.add(
                    text: text, rawText: transcript, duration: Double(samples.count) / 16000.0,
                    appName: frontApp?.localizedName, appBundleID: frontApp?.bundleIdentifier,
                    samples: samples,
                    words: timed.words,
                    segments: timed.segments,
                    modelID: model.rawValue)

                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                panel.showSuccessAndClose()

                if destination.pastes {
                    // All at once: instant paste via direct editor injection or pasteboard Command+V
                    let app = target?.externalApp ?? NSWorkspace.shared.frontmostApplication
                    if target?.ownEditor != nil {
                        injector.deliver(
                            InjectedText(text), target: target, expectedKeyword: nil,
                            keywordLength: 0, automaticGeneration: nil,
                            isValid: { [weak self] in self?.token == current },
                            onDelivered: { [weak self] in
                                guard let self, token == current else { return }
                                if destination.copies || settings.dictationAutoCopyToClipboard {
                                    Paster.copyPlainText(text)
                                }
                                reset(cancelTranscription: false, keepPanel: true)
                            },
                            onFailed: { [weak self] in
                                guard let self, token == current else { return }
                                reset(cancelTranscription: false)
                                showMessage(String(localized: "Couldn't paste dictation into this app"), .danger)
                            })
                    } else {
                        // Check accessibility permission for auto-paste into external app
                        if !Permissions.isAccessibilityTrusted() {
                            Paster.copyPlainText(text)
                            reset(cancelTranscription: false)
                            showMessage(String(localized: "Accessibility permission needed to auto-paste (Copied to clipboard)"), .neutral)
                            return
                        }

                        Paster.pasteString(text, previousApp: app) { [weak self] in
                            guard let self, token == current else { return }
                            if destination.copies || settings.dictationAutoCopyToClipboard {
                                Paster.copyPlainText(text)
                            }
                            reset(cancelTranscription: false, keepPanel: true)
                        }
                    }
                } else {
                    Paster.copyPlainText(text)
                    reset(cancelTranscription: false, keepPanel: true)
                }
            } catch {
                guard token == current else { return }
                reset(cancelTranscription: false)
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    /// Chunk spacing from the caret, else nil.
    private func insertionContext() -> DictationTextFormatter.Context? {
        if let context = DictationInsertionContext.read(in: target) { return context }
        return nil
    }

    func cancel(in editor: any InjectableTextView) {
        guard let target = target?.ownEditor, target === editor else { return }
        cancel()
    }

    func cancel() {
        guard phase != .stopping, phase != .idle || !settings.dictationEnabled else { return }
        let pendingStart = startTask
        let pendingTranscription = transcriptionTask
        let retainCancelled = settings.dictationRetainCancelled
        let capturedSnapshot = retainCancelled && phase == .listening ? capture.snapshot() : []
        let activeModel = settings.dictationModel
        let activeLanguage = settings.dictationLanguage
        let frontApp = target?.externalApp ?? NSWorkspace.shared.frontmostApplication
        reset()
        phase = .stopping
        let current = token
        stopTask = Task { [weak self] in
            guard let self else { return }
            await pendingStart?.value
            let stoppedSamples = await capture.stop()
            let samplesToKeep = stoppedSamples.isEmpty ? capturedSnapshot : stoppedSamples
            if retainCancelled, samplesToKeep.count >= 8_000,
                settings.dictationTranscriptionProvider == .parakeet,
                models.isInstalled(activeModel)
            {
                if let timed = try? await models.transcribeTimed(
                    samplesToKeep, model: activeModel, language: activeLanguage,
                    useVAD: settings.dictationVADEnabled
                ), !timed.text.isEmpty {
                    historyStore.add(
                        text: timed.text,
                        rawText: timed.text,
                        duration: Double(samplesToKeep.count) / Double(DictationWire.sampleRate),
                        appName: frontApp?.localizedName,
                        appBundleID: frontApp?.bundleIdentifier,
                        samples: samplesToKeep,
                        words: timed.words,
                        segments: timed.segments,
                        modelID: activeModel.rawValue
                    )
                }
            }
            await pendingTranscription?.value
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

    private func reset(cancelTranscription: Bool = true, keepPanel: Bool = false) {
        token = UUID()
        livePreviewCoordinator.stop()
        panel.state.previewText = ""
        panel.state.commandModeText = nil
        panel.state.isLockedHandsFree = false
        panel.state.isWhisperMode = false
        panel.state.isMuted = false
        panel.state.isMicSilent = false
        panel.state.isClamshellMuffled = false
        panel.state.isRawMode = false
        panel.state.onToggleMute = nil
        rawModeSession = false
        isHandsFreeLocked = false
        commandModeSelectedText = nil
        if cancelTranscription { transcriptionTask?.cancel() }
        startTask = nil
        transcriptionTask = nil
        phase = .idle
        target = nil
        field = nil
        if !keepPanel {
            panel.close()
        }
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

    /// Superwhisper-style media file transcription
    func transcribeFile(url: URL? = nil) {
        if let url {
            Task { @MainActor in
                await executeFileTranscription(from: url)
            }
            return
        }

        let panel = NSOpenPanel()
        panel.title = String(localized: "Select Audio or Video File to Transcribe")
        panel.prompt = String(localized: "Transcribe")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.movie,
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType.mp3,
            UTType.wav,
            UTType.aiff,
            UTType(filenameExtension: "m4a") ?? .audio,
            UTType(filenameExtension: "flac") ?? .audio,
            UTType(filenameExtension: "aac") ?? .audio,
            UTType(filenameExtension: "ogg") ?? .audio
        ]

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task { @MainActor [weak self] in
                await self?.executeFileTranscription(from: selectedURL)
            }
        }
    }

    private func executeFileTranscription(from url: URL) async {
        showMessage(String(localized: "Transcribing \(url.lastPathComponent)…"), .neutral)
        do {
            let samples = try await DictationFileTranscriber.extractSamples(from: url)
            guard !samples.isEmpty else {
                showMessage(String(localized: "No audio data found in \(url.lastPathComponent)"), .danger)
                return
            }

            let language = settings.dictationLanguage
            var timed = TimedTranscript(text: "")
            var usedModelID = settings.dictationModel.rawValue
            if settings.dictationTranscriptionProvider == .groq {
                guard !settings.groqAPIKey.isEmpty else {
                    throw GroqAudioService.GroqAudioError.missingAPIKey
                }
                let text = try await groqAudio.transcribe(
                    samples: samples,
                    apiKey: settings.groqAPIKey,
                    model: settings.dictationGroqTranscriptionModel,
                    language: language
                )
                timed = TimedTranscript(text: text)
                usedModelID = settings.dictationGroqTranscriptionModel
            } else {
                var model = settings.dictationModel
                if settings.dictationHindiMode == .whisperApex, models.isInstalled(.whisperApex) {
                    model = .whisperApex
                } else if settings.dictationBengaliMode == .indicFlex, models.isInstalled(.indicFlex) {
                    model = .indicFlex
                }
                if !models.isInstalled(model) {
                    showMessage(String(localized: "Download the dictation model in Settings first"), .danger)
                    return
                }
                usedModelID = model.rawValue
                timed = try await models.transcribeTimed(
                    samples,
                    model: model,
                    language: language,
                    useVAD: settings.dictationVADEnabled,
                    diarizeSpeakers: settings.dictationSpeakerCount
                )
            }
            let transcript = timed.text

            var processed = transcript
            processed = DictationTextFormatter.collapseRepetitions(processed)
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
                    idleRelease: settings.dictationS1IdleRelease,
                    bengaliMode: settings.dictationBengaliMode,
                    hindiMode: settings.dictationHindiMode
                )
                let polishProvider: DictationPolishProvider =
                    (settings.dictationPolishProvider == .groq && !settings.groqAPIKey.isEmpty) ? .groq : .localS1
                processed = await TranscriptAIService.polishLongTranscript(
                    processed,
                    provider: polishProvider,
                    s1Settings: s1,
                    groqAPIKey: settings.groqAPIKey,
                    groqModel: settings.dictationGroqPolishModel,
                    polisher: s1Polisher,
                    groq: groqPolish
                )
                processed = dictionaryStore.applyDictionaryAndPacks(processed)
                processed = dictionaryStore.applySnippets(processed)
            }

            if settings.dictationBengaliMode == .avroPhonetic {
                processed = AvroPhoneticConverter.convert(processed)
            }
            if settings.dictationHindiMode == .phoneticEngine {
                processed = HinglishPhoneticConverter.convert(processed)
            }

            let text = DictationTextFormatter.format(
                processed, context: nil,
                adaptCapitalization: settings.dictationAdaptsCapitalization
            )

            guard !text.isEmpty else {
                showMessage(String(localized: "No speech recognized in file"), .neutral)
                return
            }

            lastDictation = text
            let fileID = UUID()
            let wavName = "\(fileID.uuidString).wav"
            let wavURL = historyStore.store.audioDirectory.appending(path: wavName)
            DictationHistoryStore.writeWAV(samples: samples, to: wavURL)
            let record = TranscriptRecord(
                id: fileID,
                kind: .fileImport,
                title: url.deletingPathExtension().lastPathComponent,
                createdAt: Date(),
                duration: Double(samples.count) / Double(DictationWire.sampleRate),
                text: text,
                rawText: transcript,
                segments: timed.segments,
                sourceURL: url.path,
                audioFilename: FileManager.default.fileExists(atPath: wavURL.path) ? wavName : nil,
                modelID: usedModelID
            )
            historyStore.store.upsert(record)
            Paster.copyPlainText(text)
            showMessage(String(localized: "\(url.lastPathComponent) transcribed & copied to clipboard"), .success)
        } catch {
            showMessage(error.localizedDescription, .danger)
        }
    }
}

/// Which editor a mic session belongs to, so only that field's button shows it running.
struct DictationField: Equatable {
    let editor: ObjectIdentifier
    var isTranscribing = false
}
