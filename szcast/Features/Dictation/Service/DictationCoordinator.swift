import AppKit
import AVFoundation
import OSLog
import UniformTypeIdentifiers

@MainActor
@Observable
final class DictationCoordinator {
    struct StageTelemetry: Sendable {
        let audioSeconds: Double
        let preprocessMs: Double
        let vadMs: Double
        let asrMs: Double
        let formatAndPolishMs: Double
        let totalMs: Double
        let wordCount: Int
        let modelID: String

        var rtf: Double {
            audioSeconds > 0 ? (totalMs / 1000.0) / audioSeconds : 0
        }

        var summaryLine: String {
            String(
                format: "Audio %.2fs · Prep %.0fms · VAD %.0fms · ASR %.0fms · Format %.0fms · Total %.0fms · %.2fx RTF",
                audioSeconds, preprocessMs, vadMs, asrMs, formatAndPolishMs, totalMs, rtf
            )
        }
    }

    private enum Phase { case idle, starting, listening, transcribing, stopping }

    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationLatency")

    private let settings: AppSettings
    private let hotKeys: HotKeyManager
    let models: DictationModelStore
    let dictionaryStore = DictationDictionaryStore()
    let historyStore = DictationHistoryStore()
    let s1Downloader = DictationS1Downloader()
    private let s1Polisher = DictationS1Polisher()
    private let groqAudio = GroqAudioService()
    private let deepgramAudio = DeepgramAudioService()
    private let groqPolish = GroqPolishService()
    private let livePreviewCoordinator = DictationLivePreviewCoordinator()
    let transformStore = DictationTransformStore()
    private(set) var lastDictation: String?
    private(set) var lastStageTelemetry: StageTelemetry?
    private(set) var lastExecutedVoiceCommand: DictationTextFormatter.VoiceMetaCommand?
    private(set) var lastDeliveryWasDirectAX = false
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
    @ObservationIgnored private var releaseGraceTask: Task<Void, Never>?
    @ObservationIgnored private var autoLearnTask: Task<Void, Never>?
    @ObservationIgnored private var speculativeTask: Task<Void, Never>?
    @ObservationIgnored private var speculativeCoveredSample = 0
    @ObservationIgnored private var speculativeChunks: [(text: String, words: [TranscriptWord], segments: [TranscriptSegment])] = []
    @ObservationIgnored private var captureStartInstant: Double = 0
    @ObservationIgnored private var deepgramStream: DeepgramStreamingSession?
    @ObservationIgnored private var deepgramStreamActive = false
    @ObservationIgnored private var pendingStartCue: UUID?
    @ObservationIgnored private var finishWhenStarted = false
    @ObservationIgnored private var rawModeSession = false
    @ObservationIgnored private var target: InjectionTarget?
    /// The field a mic button is dictating into; nil for a shortcut's session.
    private(set) var field: DictationField?

    private var effectiveOtherAudioMode: DictationOtherAudioMode {
        settings.dictationPauseMedia ? .pause : settings.dictationOtherAudioMode
    }

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
        self.dictionaryStore.selfLearningEnabled = settings.dictationAutoLearnDictionary
        panel.onAccept = { [weak self] in self?.accept() }
        panel.onCancel = { [weak self] in self?.cancel() }
        capture.onLevels = { [weak self] levels in
            guard let self else { return }
            panel.state.levels = levels
            panel.state.isSpeechActive = levels.contains { $0 > 0.14 }
            if pendingStartCue == token { playStartCue() }
        }
        capture.onLimit = { [weak self] in self?.accept() }
        capture.onAutoStopSilence = { [weak self] in self?.accept() }
        capture.onSilenceWarning = { [weak self] silent in
            self?.panel.state.isMicSilent = silent
        }
        capture.onClippingWarning = { clipping in
            if clipping {
                Self.logger.warning("Microphone signal clipping detected")
            }
        }
        capture.onClamshellWarning = { [weak self] muffled in
            self?.panel.state.isClamshellMuffled = muffled
        }
        capture.onSamples = Self.makeSampleHandler(
            coordinator: self, livePreview: livePreviewCoordinator
        )
        capture.onPauseChunk = Self.makePauseChunkHandler(coordinator: self)
        livePreviewCoordinator.onPreviewText = { [weak self] preview in
            Task { @MainActor [weak self] in
                guard let self, phase == .listening else { return }
                panel.updatePreviewText(preview)
            }
        }
        self.lastDictation = historyStore.items.first?.text
        historyStore.skipAudioArchiveOnSuccess = (settings.dictationAudioRetentionDays == 0)
        syncCapturePreferences()
    }

    nonisolated static func makeSampleHandler(
        coordinator: DictationCoordinator,
        livePreview: DictationLivePreviewCoordinator
    ) -> @Sendable ([Float]) -> Void {
        { [weak coordinator] samples in
            livePreview.feed(samples)
            Task { @MainActor [weak coordinator] in
                guard let coordinator, coordinator.deepgramStreamActive,
                      let stream = coordinator.deepgramStream
                else { return }
                await stream.sendPCM(samples)
            }
        }
    }

    nonisolated static func makePauseChunkHandler(
        coordinator: DictationCoordinator
    ) -> @Sendable (Int, [Float]) -> Void {
        { [weak coordinator] rangeEndSample, chunk in
            Task { @MainActor [weak coordinator] in
                coordinator?.handlePauseChunk(rangeEndSample: rangeEndSample, chunk: chunk)
            }
        }
    }

    func applyAudioRetentionPolicy() {
        historyStore.applyRetentionPolicy(days: settings.dictationAudioRetentionDays)
    }

    /// Exports a redacted hardware, settings, permission, and timing bundle (zero transcripts, keys, or secrets).
    func redactedDiagnosticBundleJSON() -> String {
        let resolved = resolvedLocalModelAndLanguage()
        let payload: [String: Any] = [
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "physicalMemoryGB": Int((ProcessInfo.processInfo.physicalMemory / 1_073_741_824)),
            "transcriptionProvider": settings.dictationTranscriptionProvider.rawValue,
            "activeModel": resolved.model.rawValue,
            "activeModelInstalled": models.isInstalled(resolved.model),
            "polishEnabled": settings.dictationS1Enabled,
            "polishProvider": settings.dictationPolishProvider.rawValue,
            "captureConfig": [
                "mode": settings.dictationMode.rawValue,
                "warmPreRoll": settings.dictationWarmPreRoll,
                "voiceProcessing": settings.dictationVoiceProcessing,
                "vadEnabled": settings.dictationVADEnabled,
                "whisperMode": settings.dictationWhisperMode,
                "pillPosition": settings.dictationPillPosition.rawValue,
                "compactPill": settings.dictationCompactPill,
                "audioRetentionDays": settings.dictationAudioRetentionDays
            ],
            "permissions": [
                "accessibilityTrusted": Permissions.isAccessibilityTrusted()
            ],
            "lastTelemetry": lastStageTelemetry.map { t in
                [
                    "audioSeconds": t.audioSeconds,
                    "preprocessMs": t.preprocessMs,
                    "vadMs": t.vadMs,
                    "asrMs": t.asrMs,
                    "formatAndPolishMs": t.formatAndPolishMs,
                    "totalMs": t.totalMs,
                    "rtf": t.rtf,
                    "wordCount": t.wordCount,
                    "modelID": t.modelID
                ] as [String: Any]
            } ?? NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }

    func syncCapturePreferences() {
        let shouldArm = settings.dictationEnabled && settings.dictationWarmPreRoll
        capture.configureWarmPreRoll(
            enabled: shouldArm,
            microphoneID: settings.dictationMicrophone,
            voiceProcessing: settings.dictationVoiceProcessing
        )
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.dictationEnabled else { return }
        guard enabled else {
            settings.dictationEnabled = false
            syncCapturePreferences()
            enableTask?.cancel()
            cancel()
            DictationLlamaServerManager.shared.stop()
            Task { [models] in await models.release() }
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
            syncCapturePreferences()
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

    /// Short tap of the hold-to-talk modifier key (e.g. Fn): stops an active hands-free session cleanly.
    func holdTapped() {
        guard settings.dictationEnabled, phase != .stopping else { return }
        if phase == .starting || phase == .listening,
           isHandsFreeLocked || settings.dictationMode == .toggle
        {
            isHandsFreeLocked = false
            panel.state.isLockedHandsFree = false
            finishWhenStarted = false
            finish()
        }
    }

    /// Rapid double-tap of the hold-to-talk modifier key (e.g. Fn): toggles hands-free recording.
    func holdDoubleTapped() {
        guard settings.dictationEnabled, phase != .stopping else { return }
        if phase == .starting || phase == .listening {
            isHandsFreeLocked = false
            panel.state.isLockedHandsFree = false
            finishWhenStarted = false
            finish()
            return
        }
        guard phase == .idle else { return }
        guard settings.dictationDoubleTapToLock else { return }
        lastPressTime = .distantPast
        releaseGraceTask?.cancel()
        releaseGraceTask = nil
        rawModeSession = false
        isHandsFreeLocked = true
        panel.state.isLockedHandsFree = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        begin(target: InjectionTarget.current())
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
        let wasHandsFreeLocked = isHandsFreeLocked

        if phase != .idle {
            // Second press inside the double-tap window locks an active push-to-talk start hands-free.
            if !rawMode,
               settings.dictationMode == .pushToTalk,
               settings.dictationDoubleTapToLock,
               !wasHandsFreeLocked,
               phase == .starting || phase == .listening,
               interval < 0.45
            {
                releaseGraceTask?.cancel()
                releaseGraceTask = nil
                isHandsFreeLocked = true
                finishWhenStarted = false
                panel.state.isLockedHandsFree = true
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                return
            }
            if wasHandsFreeLocked || settings.dictationMode == .toggle || rawMode {
                isHandsFreeLocked = false
                panel.state.isLockedHandsFree = false
                finishWhenStarted = false
                finish()
            }
            return
        }
        isHandsFreeLocked = false
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

    private var currentS1Settings: DictationS1Settings {
        DictationS1Settings(
            enabled: settings.dictationS1Enabled,
            tone: settings.dictationS1Tone,
            structure: settings.dictationS1Structure,
            context: settings.dictationS1Context,
            idleRelease: settings.dictationS1IdleRelease,
            bengaliMode: settings.dictationBengaliMode,
            hindiMode: settings.dictationHindiMode
        )
    }

    func prewarm() {
        guard settings.dictationEnabled else { return }
        if settings.dictationTranscriptionProvider == .local {
            models.ensurePrewarmed(settings.dictationModel)
        }
        if settings.dictationLivePreviewEnabled {
            livePreviewCoordinator.prewarm(
                locale: DictationLanguage.previewLocale(for: settings.dictationLanguage))
        }
        if settings.dictationS1Enabled,
           DictationPolishProvider.resolved(
               preferred: settings.dictationPolishProvider,
               groqAPIKey: settings.groqAPIKey
           ) == .localS1 {
            DictationLlamaServerManager.shared.startDaemon(
                idleRelease: settings.dictationS1IdleRelease,
                settings: currentS1Settings
            )
        }
    }

    private func begin(target: InjectionTarget?) {
        releaseGraceTask?.cancel()
        releaseGraceTask = nil
        autoLearnTask?.cancel()
        autoLearnTask = nil
        if settings.dictationTranscriptionProvider == .local {
            guard models.isInstalled(settings.dictationModel) else {
                field = nil
                showMessage(String(localized: "Download the dictation model in Settings first"), .danger)
                return
            }
            models.prewarm(settings.dictationModel)
        } else {
            let cloudProvider = settings.dictationCloudSpeechProvider
            guard DictationCloudSpeechService.hasAPIKey(
                for: cloudProvider,
                groqAPIKey: settings.groqAPIKey,
                deepgramAPIKey: settings.deepgramAPIKey
            ) else {
                field = nil
                showMessage(DictationCloudSpeechService.missingKeyPrompt(for: cloudProvider), .danger)
                return
            }
        }
        if settings.dictationS1Enabled,
           DictationPolishProvider.resolved(
               preferred: settings.dictationPolishProvider,
               groqAPIKey: settings.groqAPIKey
           ) == .localS1 {
            DictationLlamaServerManager.shared.startDaemon(
                idleRelease: settings.dictationS1IdleRelease,
                settings: currentS1Settings
            )
        }
        token = UUID()
        let current = token
        phase = .starting
        finishWhenStarted = false
        speculativeTask?.cancel()
        speculativeTask = nil
        speculativeCoveredSample = 0
        speculativeChunks = []
        captureStartInstant = CFAbsoluteTimeGetCurrent()
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
        panel.state.onAccept = { [weak self] in self?.finish() }
        panel.state.onCancel = { [weak self] in self?.cancel() }
        panel.state.onSelectLanguage = { [weak self] newLanguage in
            self?.switchLanguageMidSession(to: newLanguage)
        }
        let caretRect = settings.dictationPillPosition == .nearCaret && target?.ownEditor == nil
            ? DictationInsertionContext.focusedCaretRect(in: target?.externalApp)
            : nil
        panel.show(
            position: settings.dictationPillPosition,
            compact: settings.dictationCompactPill,
            caretRect: caretRect,
            activeLanguage: settings.dictationLanguage
        )
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        pendingStartCue = settings.dictationPlaysSounds ? current : nil
        if pendingStartCue == nil { audioDucker.begin(mode: effectiveOtherAudioMode) }
        if settings.dictationTranscriptionProvider == .cloud,
           settings.dictationCloudSpeechProvider == .deepgram,
           !settings.deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let stream = deepgramStream ?? DeepgramStreamingSession()
            deepgramStream = stream
            deepgramStreamActive = true
            let dgKey = settings.deepgramAPIKey
            let dgModel = settings.dictationDeepgramModel
            let dgLang = settings.dictationLanguage
            let dgTerms = mergedVocabularyHints()
            Task {
                await stream.start(apiKey: dgKey, model: dgModel, language: dgLang, keyterms: dgTerms)
            }
        } else {
            deepgramStreamActive = false
        }
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await capture.start(
                    microphoneID: settings.dictationMicrophone,
                    whisperMode: settings.dictationWhisperMode,
                    allowLongCapture: isHandsFreeLocked || rawModeSession,
                    startMuted: false,
                    autoStopSilenceSeconds: settings.dictationAutoStopSilenceSeconds,
                    voiceProcessing: settings.dictationVoiceProcessing
                )
                guard token == current, settings.dictationEnabled else {
                    _ = await capture.stop()
                    return
                }
                phase = .listening
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

    private func handlePauseChunk(rangeEndSample: Int, chunk: [Float]) {
        guard phase == .listening,
              settings.dictationEnabled,
              settings.dictationTranscriptionProvider == .local,
              !rawModeSession,
              commandModeSelectedText == nil,
              speculativeTask == nil,
              !models.transcribing,
              rangeEndSample > speculativeCoveredSample,
              chunk.count >= 24_000,
              isHandsFreeLocked || rangeEndSample >= 56_000 || (CFAbsoluteTimeGetCurrent() - captureStartInstant) >= 3.5
        else { return }

        let resolved = resolvedLocalModelAndLanguage()
        let model = resolved.model
        guard models.isInstalled(model) else { return }
        let language = resolved.language
        let whisperMode = settings.dictationWhisperMode
        let current = token
        let offsetSeconds = Double(speculativeCoveredSample) / Double(DictationWire.sampleRate)

        speculativeTask = Task { [weak self] in
            guard let self else { return }
            defer { self.speculativeTask = nil }
            let conditioned = await Task.detached(priority: .userInitiated) {
                DictationAudioChunks.conditionForTranscription(chunk, whisperMode: whisperMode)
            }.value
            guard !Task.isCancelled, token == current else { return }
            guard let timed = try? await models.transcribeTimed(
                conditioned,
                model: model,
                language: language,
                useVAD: false
            ), !Task.isCancelled, token == current else { return }

            let shiftedWords = timed.words.map {
                TranscriptWord(text: $0.text, start: $0.start + offsetSeconds, end: $0.end + offsetSeconds, confidence: $0.confidence)
            }
            let shiftedSegments = timed.segments.map { seg in
                TranscriptSegment(
                    id: seg.id,
                    speaker: seg.speaker,
                    text: seg.text,
                    start: seg.start + offsetSeconds,
                    end: seg.end + offsetSeconds,
                    words: seg.words.map {
                        TranscriptWord(text: $0.text, start: $0.start + offsetSeconds, end: $0.end + offsetSeconds, confidence: $0.confidence)
                    }
                )
            }
            speculativeCoveredSample = rangeEndSample
            let clean = timed.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                speculativeChunks.append((clean, shiftedWords, shiftedSegments))
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
            audioDucker.begin(mode: effectiveOtherAudioMode)
        }
    }

    func released() {
        guard settings.dictationMode == .pushToTalk else { return }
        if isHandsFreeLocked { return }
        if phase == .starting { finishWhenStarted = true }
        if phase == .listening {
            let current = token
            releaseGraceTask?.cancel()
            releaseGraceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard let self,
                      !Task.isCancelled,
                      token == current,
                      phase == .listening,
                      !isHandsFreeLocked else { return }
                accept()
            }
        }
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
            audioDucker.end(mode: effectiveOtherAudioMode)
        }

        let current = token
        let resolved = resolvedLocalModelAndLanguage()
        let model = resolved.model
        let language = resolved.language
        let acceptStart = CFAbsoluteTimeGetCurrent()
        let whisperMode = settings.dictationWhisperMode
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            let rawSamples = await capture.stop()
            await speculativeTask?.value
            speculativeTask = nil
            guard token == current else { return }
            let destination = field == nil ? settings.dictationDestination : .paste
            if rawSamples.count < 1_600 {
                reset(cancelTranscription: false)
                if settings.dictationMode != .pushToTalk {
                    showMessage(String(localized: "No speech was recorded"), .danger)
                }
                return
            }

            let frontApp = target?.externalApp ?? NSWorkspace.shared.frontmostApplication
            let coveredOffset = (speculativeCoveredSample > 0
                && speculativeCoveredSample <= rawSamples.count
                && settings.dictationTranscriptionProvider == .local
                && !rawModeSession
                && commandModeSelectedText == nil) ? speculativeCoveredSample : 0
            let tailSlice = coveredOffset > 0 ? Array(rawSamples[coveredOffset...]) : rawSamples
            let hasSubstantialTail = tailSlice.count >= 1_600

            let prepStart = CFAbsoluteTimeGetCurrent()
            let conditionedTail: [Float] = hasSubstantialTail
                ? await Task.detached(priority: .userInitiated) {
                    DictationAudioChunks.conditionForTranscription(tailSlice, whisperMode: whisperMode)
                }.value
                : []
            guard token == current else { return }
            let prepMs = (CFAbsoluteTimeGetCurrent() - prepStart) * 1000

            do {
                let asrStart = CFAbsoluteTimeGetCurrent()
                var timed = TimedTranscript(text: "")
                if coveredOffset > 0 {
                    var combinedTexts = speculativeChunks.map(\.text)
                    var combinedWords = speculativeChunks.flatMap(\.words)
                    var combinedSegments = speculativeChunks.flatMap(\.segments)
                    if hasSubstantialTail {
                        let tailTimed = try await models.transcribeTimed(
                            conditionedTail,
                            model: model,
                            language: language,
                            useVAD: settings.dictationVADEnabled
                        )
                        let cleanTail = tailTimed.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanTail.isEmpty { combinedTexts.append(cleanTail) }
                        let offsetSec = Double(coveredOffset) / Double(DictationWire.sampleRate)
                        combinedWords.append(contentsOf: tailTimed.words.map {
                            TranscriptWord(text: $0.text, start: $0.start + offsetSec, end: $0.end + offsetSec, confidence: $0.confidence)
                        })
                        combinedSegments.append(contentsOf: tailTimed.segments.map { seg in
                            TranscriptSegment(
                                id: seg.id,
                                speaker: seg.speaker,
                                text: seg.text,
                                start: seg.start + offsetSec,
                                end: seg.end + offsetSec,
                                words: seg.words.map {
                                    TranscriptWord(text: $0.text, start: $0.start + offsetSec, end: $0.end + offsetSec, confidence: $0.confidence)
                                }
                            )
                        })
                    }
                    timed = TimedTranscript(
                        text: combinedTexts.joined(separator: " "),
                        words: combinedWords,
                        segments: combinedSegments
                    )
                } else if settings.dictationTranscriptionProvider == .cloud {
                    var streamText: String?
                    if settings.dictationCloudSpeechProvider == .deepgram, deepgramStreamActive, let stream = deepgramStream {
                        deepgramStreamActive = false
                        streamText = await stream.finish()
                    }
                    if let streamText, !streamText.isEmpty {
                        timed = TimedTranscript(text: streamText)
                    } else {
                        do {
                            let hints = mergedVocabularyHints()
                            let result = try await DictationCloudSpeechService.transcribe(
                                provider: settings.dictationCloudSpeechProvider,
                                samples: conditionedTail,
                                groqAudio: groqAudio,
                                deepgramAudio: deepgramAudio,
                                groqAPIKey: settings.groqAPIKey,
                                deepgramAPIKey: settings.deepgramAPIKey,
                                groqModel: settings.dictationGroqTranscriptionModel,
                                deepgramModel: settings.dictationDeepgramModel,
                                language: language,
                                keyterms: hints,
                                groqPrompt: buildGroqPrompt(extraTerms: hints)
                            )
                            timed = TimedTranscript(text: result.text)
                        } catch {
                            if error is CancellationError { throw error }
                            guard let fallbackModel = installedFallbackLocalModel() else { throw error }
                            Self.logger.warning(
                                "Cloud STT failed (\(error.localizedDescription)); failing over locally to \(fallbackModel.rawValue)"
                            )
                            timed = try await models.transcribeTimed(
                                conditionedTail,
                                model: fallbackModel,
                                language: language,
                                useVAD: settings.dictationVADEnabled
                            )
                        }
                    }
                } else {
                    timed = try await models.transcribeTimed(
                        conditionedTail,
                        model: model,
                        language: language,
                        useVAD: settings.dictationVADEnabled
                    )
                }
                let wallAsrMs = (CFAbsoluteTimeGetCurrent() - asrStart) * 1000
                let formatStart = CFAbsoluteTimeGetCurrent()
                let transcript = timed.text
                guard token == current else { return }

                var processed = transcript
                processed = DictationTextFormatter.stripHallucinations(processed)
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

                let bundleID = frontApp?.bundleIdentifier
                let effectiveApp: NSRunningApplication? = target?.ownEditor == nil ? frontApp : nil
                let effectiveBundleID = target?.ownEditor == nil ? bundleID : nil
                let windowMeta = DictationInsertionContext.readWindowMetadata(for: effectiveApp)
                let appCategory = AppStyleRouter.category(
                    for: effectiveBundleID,
                    windowTitle: windowMeta.windowTitle,
                    documentURL: windowMeta.documentURL
                )

                if settings.dictationVoiceCommandsEnabled,
                   !rawModeSession,
                   self.commandModeSelectedText == nil,
                   let metaCommand = DictationTextFormatter.extractVoiceMetaCommand(processed) {
                    let executed = executeVoiceMetaCommand(
                        metaCommand,
                        frontApp: effectiveApp,
                        ownEditor: target?.ownEditor
                    )
                    reset(cancelTranscription: false)
                    if executed {
                        panel.showSuccessAndClose()
                        showMessage(Self.voiceCommandStatusTitle(metaCommand), .success)
                    } else {
                        showMessage(String(localized: "Accessibility permission needed for voice commands"), .neutral)
                    }
                    return
                }

                if settings.dictationCodeAndMarkdownSyntax,
                   !rawModeSession,
                   self.commandModeSelectedText == nil {
                    processed = DictationTextFormatter.formatSyntaxCommands(
                        processed,
                        isCodeContext: appCategory == .code,
                        isNotesContext: appCategory == .notes
                    )
                }

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
                    s1 = AppStyleRouter.resolvedS1Settings(
                        base: s1,
                        bundleID: effectiveBundleID,
                        windowTitle: windowMeta.windowTitle,
                        documentURL: windowMeta.documentURL
                    )
                }

                let polishProvider = DictationPolishProvider.resolved(
                    preferred: settings.dictationPolishProvider,
                    groqAPIKey: settings.groqAPIKey
                )

                if let selectedText = self.commandModeSelectedText, !selectedText.isEmpty {
                    // Command Mode: Rewrites highlighted text using voice instruction
                    if let rewritten = await TranscriptAIService.runTransform(
                        text: selectedText,
                        instruction: processed,
                        provider: polishProvider,
                        s1Settings: s1,
                        groqAPIKey: settings.groqAPIKey,
                        groqModel: settings.dictationGroqPolishModel,
                        polisher: s1Polisher,
                        groq: groqPolish
                    ) {
                        processed = rewritten
                    } else {
                        processed = await s1Polisher.transform(text: selectedText, instruction: processed, settings: s1)
                    }
                } else if settings.dictationVoiceCommandsEnabled,
                          !rawModeSession,
                          let askQuery = DictationTextFormatter.extractAskAIQuery(processed) {
                    if let answer = await TranscriptAIService.runTransform(
                        text: askQuery,
                        instruction: "Answer the user's question concisely and directly in plain text with no markdown fences or chatter.",
                        provider: polishProvider,
                        s1Settings: s1,
                        groqAPIKey: settings.groqAPIKey,
                        groqModel: settings.dictationGroqPolishModel,
                        polisher: s1Polisher,
                        groq: groqPolish
                    ), !answer.isEmpty {
                        processed = answer
                    }
                } else if settings.dictationAutoApplyTransform,
                          let transform = transformStore.transform(with: settings.dictationActiveTransformID) {
                    // Custom Transform applied to dictation
                    if let transformed = await TranscriptAIService.runTransform(
                        text: processed,
                        instruction: transform.systemPrompt,
                        provider: polishProvider,
                        s1Settings: s1,
                        groqAPIKey: settings.groqAPIKey,
                        groqModel: settings.dictationGroqPolishModel,
                        polisher: s1Polisher,
                        groq: groqPolish
                    ) {
                        processed = transformed
                    } else {
                        processed = await s1Polisher.transform(text: processed, instruction: transform.systemPrompt, settings: s1)
                    }
                } else if settings.dictationS1Enabled, !rawModeSession,
                          DictationS1Settings.needsLLMCleanup(processed, s1Settings: s1) {
                    processed = await TranscriptAIService.polishLongTranscript(
                        processed,
                        provider: polishProvider,
                        s1Settings: s1,
                        vocabularyTerms: dictionaryStore.promptVocabularyHint(for: processed),
                        groqAPIKey: settings.groqAPIKey,
                        groqModel: settings.dictationGroqPolishModel,
                        polisher: s1Polisher,
                        groq: groqPolish
                    )
                    // Authoritative post-pass: ensure user custom words, vocabulary packs, snippets, and symbols survive normalization
                    processed = dictionaryStore.applyDictionaryAndPacks(processed)
                    processed = dictionaryStore.applySnippets(processed)
                    if settings.dictationCodeAndMarkdownSyntax {
                        processed = DictationTextFormatter.formatSyntaxCommands(
                            processed,
                            isCodeContext: appCategory == .code,
                            isNotesContext: appCategory == .notes
                        )
                    }
                    if settings.dictationSpokenPunctuation {
                        processed = DictationTextFormatter.normalizePostPolishSymbols(processed)
                    }
                }

                processed = AvroPhoneticConverter.normalizeIfNeeded(
                    processed,
                    bengaliMode: settings.dictationBengaliMode,
                    isCloud: settings.dictationTranscriptionProvider == .cloud,
                    localModel: model
                )
                processed = HinglishPhoneticConverter.normalizeIfNeeded(
                    processed,
                    hindiMode: settings.dictationHindiMode,
                    isCloud: settings.dictationTranscriptionProvider == .cloud,
                    localModel: model
                )

                if !rawModeSession {
                    processed = DictationTextFormatter.formatSpokenEnumerations(processed)
                }

                // A mic belongs to its field: the text goes in there, never to the clipboard.
                let context = destination.pastes ? insertionContext() : nil
                var text = DictationTextFormatter.format(
                    processed, context: context,
                    adaptCapitalization: settings.dictationAdaptsCapitalization)
                if settings.dictationAutoAppRouting {
                    text = AppStyleRouter.applyCategoryFormatting(
                        text,
                        bundleID: effectiveBundleID,
                        windowTitle: windowMeta.windowTitle,
                        documentURL: windowMeta.documentURL
                    )
                }
                let submitSplit: (text: String, shouldSubmit: Bool)
                if destination.pastes,
                   target?.ownEditor == nil,
                   settings.dictationVoiceSubmit,
                   !rawModeSession,
                   self.commandModeSelectedText == nil {
                    submitSplit = DictationTextFormatter.extractTrailingSubmitCommand(text)
                } else {
                    submitSplit = (text, false)
                }
                text = submitSplit.text
                let cursorSplit = DictationTextFormatter.extractCursorMarker(from: text)
                text = cursorSplit.text
                let cursorOffset = cursorSplit.cursorOffsetFromEnd
                let plainTextOnly = (appCategory == .code || appCategory == .notes || rawModeSession)
                let target = self.target
                guard !text.isEmpty else {
                    reset(cancelTranscription: false)
                    return
                }

                lastDictation = text
                let formatMs = (CFAbsoluteTimeGetCurrent() - formatStart) * 1000
                let totalMs = (CFAbsoluteTimeGetCurrent() - acceptStart) * 1000
                let audioSeconds = Double(rawSamples.count) / Double(DictationWire.sampleRate)
                let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
                let telemetry = StageTelemetry(
                    audioSeconds: audioSeconds,
                    preprocessMs: prepMs,
                    vadMs: timed.timings?.vadMs ?? 0,
                    asrMs: timed.timings?.asrMs ?? wallAsrMs,
                    formatAndPolishMs: formatMs,
                    totalMs: totalMs,
                    wordCount: wordCount,
                    modelID: model.rawValue
                )
                lastStageTelemetry = telemetry
                Self.logger.notice(
                    "Dictation telemetry: audio=\(audioSeconds, format: .fixed(precision: 2))s prep=\(prepMs, format: .fixed(precision: 1))ms vad=\(telemetry.vadMs, format: .fixed(precision: 1))ms asr=\(telemetry.asrMs, format: .fixed(precision: 1))ms format=\(formatMs, format: .fixed(precision: 1))ms total=\(totalMs, format: .fixed(precision: 1))ms words=\(wordCount) model=\(model.rawValue, privacy: .public)"
                )

                historyStore.addAsync(
                    text: text, rawText: transcript, duration: audioSeconds,
                    appName: frontApp?.localizedName, appBundleID: frontApp?.bundleIdentifier,
                    samples: rawSamples,
                    words: timed.words,
                    segments: timed.segments,
                    modelID: model.rawValue)

                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)

                if destination.pastes {
                    let app = target?.externalApp ?? NSWorkspace.shared.frontmostApplication
                    if target?.ownEditor != nil {
                        lastDeliveryWasDirectAX = false
                        panel.showSuccessAndClose()
                        injector.deliver(
                            InjectedText(text, cursorOffsetFromEnd: cursorOffset),
                            target: target,
                            expectedKeyword: nil,
                            keywordLength: 0,
                            automaticGeneration: nil,
                            isValid: { [weak self] in self?.token == current },
                            onDelivered: { [weak self] in
                                guard let self, token == current else { return }
                                if destination.copies || settings.dictationAutoCopyToClipboard {
                                    Paster.copyPlainText(text, plainTextOnly: plainTextOnly)
                                }
                                reset(cancelTranscription: false, keepPanel: true)
                            },
                            onFailed: { [weak self] in
                                guard let self, token == current else { return }
                                reset(cancelTranscription: false)
                                showMessage(String(localized: "Couldn't paste dictation into this app"), .danger)
                            })
                    } else if DictationInsertionContext.isSecureInputActive {
                        lastDeliveryWasDirectAX = false
                        Paster.copyConcealedText(text)
                        panel.state.onCopyFallback = { Paster.copyConcealedText(text) }
                        panel.showFallbackCard(
                            text: text,
                            subtitle: String(localized: "Secure input active — copied (⌘V when ready)")
                        )
                        reset(cancelTranscription: false, keepPanel: true)
                        showMessage(String(localized: "Secure input active — copied (⌘V when ready)"), .neutral)
                        return
                    } else if !Permissions.isAccessibilityTrusted() {
                        lastDeliveryWasDirectAX = false
                        Paster.copyPlainText(text, plainTextOnly: plainTextOnly)
                        panel.state.onCopyFallback = {
                            Paster.copyPlainText(text, plainTextOnly: plainTextOnly)
                        }
                        panel.state.onRetryPasteFallback = { [weak self] in
                            guard let self else { return }
                            if Permissions.ensureAccessibility() {
                                Paster.pasteString(
                                    text,
                                    previousApp: NSWorkspace.shared.frontmostApplication,
                                    restorePasteboard: true,
                                    plainTextOnly: plainTextOnly
                                )
                                self.panel.close()
                            } else {
                                Paster.copyPlainText(text, plainTextOnly: plainTextOnly)
                            }
                        }
                        panel.showFallbackCard(
                            text: text,
                            subtitle: String(localized: "Copied — Enable Accessibility or press ⌘V")
                        )
                        reset(cancelTranscription: false, keepPanel: true)
                        showMessage(String(localized: "Accessibility permission needed to auto-paste (Copied to clipboard)"), .neutral)
                        return
                    } else {
                        var axBaseline: String?
                        let insertedDirectly = !submitSplit.shouldSubmit && DictationInsertionContext.tryDirectAccessibilityInsert(
                            text,
                            cursorOffsetFromEnd: cursorOffset,
                            into: app,
                            autoLearnBaseline: &axBaseline
                        )
                        if insertedDirectly {
                            lastDeliveryWasDirectAX = true
                            if destination.copies || settings.dictationAutoCopyToClipboard {
                                Paster.copyPlainText(text, plainTextOnly: plainTextOnly)
                            }
                            panel.showSuccessAndClose()
                            if let axBaseline, settings.dictationAutoLearnDictionary {
                                scheduleAutoLearnCheck(
                                    pastedText: text,
                                    baselineText: axBaseline,
                                    target: target
                                )
                            }
                            reset(cancelTranscription: false, keepPanel: true)
                        } else {
                            lastDeliveryWasDirectAX = false
                            let restoreClipboard = !(destination.copies || settings.dictationAutoCopyToClipboard)
                            let baselineFieldText = settings.dictationAutoLearnDictionary
                                ? DictationInsertionContext.readFieldText(in: target)
                                : nil

                            Paster.pasteString(
                                text,
                                previousApp: app,
                                restorePasteboard: restoreClipboard,
                                pressReturnAfter: submitSplit.shouldSubmit,
                                plainTextOnly: plainTextOnly
                            ) { [weak self] in
                                guard let self, token == current else { return }
                                if let cursorOffset, cursorOffset > 0 {
                                    Self.postLeftArrows(count: cursorOffset, toPid: app?.processIdentifier)
                                }
                                if destination.copies || settings.dictationAutoCopyToClipboard {
                                    Paster.copyPlainText(text, plainTextOnly: plainTextOnly)
                                }
                                panel.showSuccessAndClose()
                                if let baselineFieldText, settings.dictationAutoLearnDictionary {
                                    scheduleAutoLearnCheck(
                                        pastedText: text,
                                        baselineText: baselineFieldText,
                                        target: target
                                    )
                                }
                                reset(cancelTranscription: false, keepPanel: true)
                            }
                        }
                    }
                } else {
                    lastDeliveryWasDirectAX = false
                    Paster.copyPlainText(text, plainTextOnly: plainTextOnly)
                    panel.showSuccessAndClose()
                    reset(cancelTranscription: false, keepPanel: true)
                }
            } catch {
                guard token == current else { return }
                if !(error is CancellationError), rawSamples.count >= 12_800 {
                    historyStore.addAsync(
                        text: "[Dictation Recovery — failed transcription]",
                        rawText: error.localizedDescription,
                        duration: Double(rawSamples.count) / Double(DictationWire.sampleRate),
                        appName: frontApp?.localizedName,
                        appBundleID: frontApp?.bundleIdentifier,
                        samples: rawSamples,
                        modelID: model.rawValue
                    )
                    reset(cancelTranscription: false)
                    showMessage("\(error.localizedDescription) Audio saved in Dictation History.", .danger)
                } else {
                    reset(cancelTranscription: false)
                    showMessage(error.localizedDescription, .danger)
                }
            }
        }
    }

    /// Chunk spacing from the caret, else nil.
    private func insertionContext() -> DictationTextFormatter.Context? {
        guard target?.ownEditor != nil || Permissions.isAccessibilityTrusted() else { return nil }
        return DictationInsertionContext.read(in: target)
    }

    func cancel(in editor: any InjectableTextView) {
        guard let target = target?.ownEditor, target === editor else { return }
        cancel()
    }

    func cancel() {
        guard phase != .stopping, phase != .idle || !settings.dictationEnabled else { return }
        releaseGraceTask?.cancel()
        releaseGraceTask = nil
        autoLearnTask?.cancel()
        autoLearnTask = nil
        let pendingStart = startTask
        let pendingTranscription = transcriptionTask
        let retainCancelled = settings.dictationRetainCancelled
        let capturedSnapshot = retainCancelled && phase == .listening ? capture.snapshot() : []
        let activeModel = settings.dictationModel
        let activeLanguage = settings.dictationLanguage
        let frontApp = target?.externalApp ?? NSWorkspace.shared.frontmostApplication
        if phase == .listening {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
        reset()
        phase = .stopping
        let current = token
        stopTask = Task { [weak self] in
            guard let self else { return }
            await pendingStart?.value
            let stoppedSamples = await capture.stop()
            let samplesToKeep = stoppedSamples.isEmpty ? capturedSnapshot : stoppedSamples
            if retainCancelled, samplesToKeep.count >= 8_000,
                settings.dictationTranscriptionProvider == .local,
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
        releaseGraceTask?.cancel()
        autoLearnTask?.cancel()
        speculativeTask?.cancel()
        capture.configureWarmPreRoll(enabled: false, microphoneID: nil, voiceProcessing: false)
        cancel()
        cueTask?.cancel()
        audioDucker.restoreImmediately()
        models.prepareForTermination()
        s1Downloader.cancelDownload()
        DictationLlamaServerManager.shared.stop()
    }

    private func reset(cancelTranscription: Bool = true, keepPanel: Bool = false) {
        token = UUID()
        releaseGraceTask?.cancel()
        releaseGraceTask = nil
        speculativeTask?.cancel()
        speculativeTask = nil
        speculativeCoveredSample = 0
        speculativeChunks = []
        deepgramStreamActive = false
        let pendingStream = deepgramStream
        Task { await pendingStream?.cancel() }
        livePreviewCoordinator.stop()
        panel.state.previewText = ""
        panel.state.commandModeText = nil
        panel.state.isLockedHandsFree = false
        panel.state.isWhisperMode = false
        panel.state.isMuted = false
        panel.state.isMicSilent = false
        panel.state.isClamshellMuffled = false
        panel.state.isRawMode = false
        panel.state.isSpeechActive = false
        panel.state.onToggleMute = nil
        panel.state.onAccept = nil
        panel.state.onCancel = nil
        panel.state.onSelectLanguage = nil
        panel.state.onCopyFallback = nil
        panel.state.onRetryPasteFallback = nil
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
            panel.state.fallbackText = nil
            panel.state.fallbackSubtitle = nil
            panel.close()
        }
        audioDucker.end(mode: effectiveOtherAudioMode)
    }

    private func switchLanguageMidSession(to language: String?) {
        settings.dictationLanguage = language
        panel.state.activeLanguageCode = DictationLanguage.isoCode(for: language)?.uppercased()
        if phase == .listening, settings.dictationLivePreviewEnabled {
            livePreviewCoordinator.stop()
            livePreviewCoordinator.start(locale: DictationLanguage.previewLocale(for: language))
        }
    }

    private static func postLeftArrows(count: Int, toPid pid: pid_t?) {
        guard count > 0, let src = CGEventSource(stateID: .combinedSessionState) else { return }
        for _ in 0..<min(count, 40) {
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x7B, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0x7B, keyDown: false)
            else { break }
            down.flags = []
            up.flags = []
            down.setIntegerValueField(.eventSourceUserData, value: Paster.szcastEventTag)
            up.setIntegerValueField(.eventSourceUserData, value: Paster.szcastEventTag)
            if let pid {
                down.postToPid(pid)
                up.postToPid(pid)
            } else {
                down.post(tap: .cgAnnotatedSessionEventTap)
                up.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }

    private func scheduleAutoLearnCheck(
        pastedText: String,
        baselineText: String,
        target: InjectionTarget?
    ) {
        autoLearnTask?.cancel()
        let pastedClean = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pastedClean.isEmpty else { return }
        autoLearnTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled, settings.dictationAutoLearnDictionary else { return }
            guard let updatedText = DictationInsertionContext.readFieldText(in: target),
                  updatedText != baselineText else { return }
            let editedSegment = Self.extractInsertedSegment(baseline: baselineText, updated: updatedText)
            if let pair = DictationDictionaryStore.detectEditedWordPair(
                original: pastedClean,
                edited: editedSegment
            ) {
                dictionaryStore.selfLearningEnabled = true
                dictionaryStore.learnCorrection(original: pair.original, corrected: pair.corrected)
            }
        }
    }

    /// Isolates the newly inserted or manually edited span between pre-paste and post-edit field text.
    static func extractInsertedSegment(baseline: String, updated: String) -> String {
        let baseWords = baseline.split(whereSeparator: \.isWhitespace).map(String.init)
        let updatedWords = updated.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !baseWords.isEmpty else {
            return updated.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var prefix = 0
        let maxPrefix = min(baseWords.count, updatedWords.count)
        while prefix < maxPrefix, baseWords[prefix] == updatedWords[prefix] {
            prefix += 1
        }
        var suffix = 0
        let remainingBase = baseWords.count - prefix
        let remainingUpdated = updatedWords.count - prefix
        let maxSuffix = min(remainingBase, remainingUpdated)
        while suffix < maxSuffix,
              baseWords[baseWords.count - 1 - suffix] == updatedWords[updatedWords.count - 1 - suffix] {
            suffix += 1
        }
        let end = updatedWords.count - suffix
        guard prefix <= end else { return "" }
        return updatedWords[prefix..<end].joined(separator: " ")
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

    func retranscribeHistoryItem(_ item: DictationHistoryItem, using targetModel: DictationModel? = nil) {
        guard let url = historyStore.audioURL(for: item) else {
            showMessage(String(localized: "No audio file saved for this history item"), .danger)
            return
        }
        let chosenModel = targetModel ?? resolvedLocalModelAndLanguage().model
        guard models.isInstalled(chosenModel) else {
            showMessage(String(localized: "Download \(chosenModel.title) in Model Library first"), .danger)
            return
        }
        let whisperMode = settings.dictationWhisperMode
        let language = resolvedLocalModelAndLanguage().language
        showMessage(String(localized: "Re-transcribing with \(chosenModel.variantTitle)…"), .neutral)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let rawSamples = await Task.detached(priority: .userInitiated) {
                DictationHistoryStore.loadAudioSamples(from: url)
            }.value
            guard let rawSamples, !rawSamples.isEmpty else {
                self.showMessage(String(localized: "Could not read saved audio clip"), .danger)
                return
            }
            let conditioned = await Task.detached(priority: .userInitiated) {
                DictationAudioChunks.conditionForTranscription(rawSamples, whisperMode: whisperMode)
            }.value
            do {
                let timed = try await models.transcribeTimed(
                    conditioned,
                    model: chosenModel,
                    language: language,
                    useVAD: settings.dictationVADEnabled
                )
                let processed = self.applyPostProcessingPipeline(
                    transcript: timed.text,
                    bundleID: item.appBundleID,
                    model: chosenModel,
                    allowVoiceSubmit: false
                )
                guard !processed.isEmpty else {
                    self.showMessage(String(localized: "No speech detected in audio clip"), .neutral)
                    return
                }
                self.historyStore.updateTranscription(
                    id: item.id,
                    text: processed,
                    rawText: timed.text,
                    modelID: chosenModel.rawValue,
                    words: timed.words,
                    segments: timed.segments
                )
                Paster.copyPlainText(processed)
                self.showMessage(String(localized: "Updated & copied via \(chosenModel.variantTitle)"), .success)
            } catch {
                self.showMessage(error.localizedDescription, .danger)
            }
        }
    }

    private func installedFallbackLocalModel() -> DictationModel? {
        if models.isInstalled(settings.dictationModel) { return settings.dictationModel }
        return DictationModel.allCases.first { models.isInstalled($0) }
    }

    private func applyPostProcessingPipeline(
        transcript: String,
        bundleID: String?,
        model: DictationModel,
        allowVoiceSubmit: Bool
    ) -> String {
        var processed = transcript
        processed = DictationTextFormatter.stripHallucinations(processed)
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
        let appCategory = AppStyleRouter.category(for: bundleID)
        if settings.dictationCodeAndMarkdownSyntax {
            processed = DictationTextFormatter.formatSyntaxCommands(
                processed,
                isCodeContext: appCategory == .code,
                isNotesContext: appCategory == .notes
            )
        }
        processed = AvroPhoneticConverter.normalizeIfNeeded(
            processed,
            bengaliMode: settings.dictationBengaliMode,
            isCloud: false,
            localModel: model
        )
        processed = HinglishPhoneticConverter.normalizeIfNeeded(
            processed,
            hindiMode: settings.dictationHindiMode,
            isCloud: false,
            localModel: model
        )
        processed = DictationTextFormatter.formatSpokenEnumerations(processed)
        var text = DictationTextFormatter.format(
            processed, context: nil,
            adaptCapitalization: settings.dictationAdaptsCapitalization)
        if settings.dictationAutoAppRouting {
            text = AppStyleRouter.applyCategoryFormatting(text, bundleID: bundleID)
        }
        if allowVoiceSubmit, settings.dictationVoiceSubmit {
            text = DictationTextFormatter.extractTrailingSubmitCommand(text).text
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func executeVoiceMetaCommand(
        _ command: DictationTextFormatter.VoiceMetaCommand,
        frontApp: NSRunningApplication?,
        ownEditor: (any InjectableTextView)?
    ) -> Bool {
        if let ownEditor {
            lastExecutedVoiceCommand = command
            switch command {
            case .undoLast:
                ownEditor.undoManager?.undo()
            case .selectAll:
                ownEditor.selectAll(nil)
            case .copyThat:
                if let last = lastDictation, !last.isEmpty {
                    Paster.copyPlainText(last)
                }
            case .newTab:
                break
            }
            return true
        }
        guard Permissions.isAccessibilityTrusted() else { return false }
        lastExecutedVoiceCommand = command
        let pid = frontApp?.processIdentifier
        switch command {
        case .undoLast: Paster.postCommandCharacter("z", fallback: 0x06, toPid: pid)
        case .selectAll: Paster.postCommandCharacter("a", fallback: 0x00, toPid: pid)
        case .copyThat: Paster.postCommandC(toPid: pid)
        case .newTab: Paster.postCommandCharacter("t", fallback: 0x11, toPid: pid)
        }
        return true
    }

    private static func voiceCommandStatusTitle(_ command: DictationTextFormatter.VoiceMetaCommand) -> String {
        switch command {
        case .undoLast: return String(localized: "Executed: Undo")
        case .selectAll: return String(localized: "Executed: Select All")
        case .copyThat: return String(localized: "Executed: Copy")
        case .newTab: return String(localized: "Executed: New Tab")
        }
    }

    private func mergedVocabularyHints() -> [String] {
        var base = dictionaryStore.promptVocabularyHint()
        let extra = focusedWindowVocabularyTerms()
        var seen = Set(base.map { $0.lowercased() })
        for term in extra where base.count < 40 {
            if seen.insert(term.lowercased()).inserted {
                base.append(term)
            }
        }
        return base
    }

    private func focusedWindowVocabularyTerms() -> [String] {
        let app = target?.externalApp ?? NSWorkspace.shared.frontmostApplication
        guard let title = DictationInsertionContext.readWindowMetadata(for: app).windowTitle else {
            return []
        }
        return DictationDictionaryStore.extractContextVocabulary(fromWindowTitle: title)
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
        Paster.postCommandC()

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
            let rawSamples = try await DictationFileTranscriber.extractSamples(from: url)
            guard !rawSamples.isEmpty else {
                showMessage(String(localized: "No audio data found in \(url.lastPathComponent)"), .danger)
                return
            }
            let samples = DictationAudioChunks.conditionForTranscription(rawSamples)

            let resolved = resolvedLocalModelAndLanguage()
            let language = resolved.language
            var timed = TimedTranscript(text: "")
            var usedModelID = settings.dictationModel.rawValue
            if settings.dictationTranscriptionProvider == .cloud {
                let result = try await DictationCloudSpeechService.transcribe(
                    provider: settings.dictationCloudSpeechProvider,
                    samples: samples,
                    groqAudio: groqAudio,
                    deepgramAudio: deepgramAudio,
                    groqAPIKey: settings.groqAPIKey,
                    deepgramAPIKey: settings.deepgramAPIKey,
                    groqModel: settings.dictationGroqTranscriptionModel,
                    deepgramModel: settings.dictationDeepgramModel,
                    language: language,
                    keyterms: dictionaryStore.promptVocabularyHint(),
                    groqPrompt: buildGroqPrompt()
                )
                timed = TimedTranscript(text: result.text)
                usedModelID = result.modelID
            } else {
                let model = resolved.model
                if !models.isInstalled(model) {
                    showMessage(String(localized: "Download the dictation model in Model Library first"), .danger)
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
            processed = DictationTextFormatter.stripHallucinations(processed)
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
                    vocabularyTerms: dictionaryStore.promptVocabularyHint(for: processed),
                    groqAPIKey: settings.groqAPIKey,
                    groqModel: settings.dictationGroqPolishModel,
                    polisher: s1Polisher,
                    groq: groqPolish
                )
                processed = dictionaryStore.applyDictionaryAndPacks(processed)
                processed = dictionaryStore.applySnippets(processed)
            }

            processed = AvroPhoneticConverter.normalizeIfNeeded(
                processed,
                bengaliMode: settings.dictationBengaliMode,
                isCloud: settings.dictationTranscriptionProvider == .cloud,
                localModel: resolved.model
            )
            processed = HinglishPhoneticConverter.normalizeIfNeeded(
                processed,
                hindiMode: settings.dictationHindiMode,
                isCloud: settings.dictationTranscriptionProvider == .cloud,
                localModel: resolved.model
            )

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

    func activateLocalModel(_ model: DictationModel) {
        guard models.isInstalled(model) else { return }
        settings.dictationTranscriptionProvider = .local
        settings.dictationModel = model
        if settings.dictationHindiMode == .whisperApex && model != .whisperApex {
            settings.dictationHindiMode = .phoneticEngine
        }
        if settings.dictationBengaliMode == .indicFlex && model != .indicFlex {
            settings.dictationBengaliMode = .avroPhonetic
        }
        models.prewarm(model)
    }

    private func resolvedLocalModelAndLanguage() -> (model: DictationModel, language: String?) {
        let model = settings.dictationModel
        var language = settings.dictationLanguage
        if model == .indicFlex {
            let iso = DictationLanguage.isoCode(for: language)
            if iso == nil || iso == "en" {
                language = DictationLanguage.bengali.rawValue
            }
        }
        return (model, language)
    }

    private func buildGroqPrompt(extraTerms: [String]? = nil) -> String? {
        let terms = extraTerms ?? mergedVocabularyHints()
        guard !terms.isEmpty else { return nil }
        return "Vocabulary: " + terms.joined(separator: ", ")
    }
}

/// Which editor a mic session belongs to, so only that field's button shows it running.
struct DictationField: Equatable {
    let editor: ObjectIdentifier
    var isTranscribing = false
}
