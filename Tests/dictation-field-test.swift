import AppKit
import SwiftUI

@main
@MainActor
struct DictationFieldTest {
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try await testDelivery()
        try await testScopedCancellation()
        try await testChatSwitch()
        try await testWindowClose()
        try await testQueuedCancellation(closing: false)
        try await testQueuedCancellation(closing: true)
        try await testSoundsOff()
        try await testSounds()
        try await testCancelSilently()
        try await testCancelDuringStartCue()
        try await testBluetoothStartCue()
        try await testHoldAndDoubleTapHandsFree()
        try await testWisprVoiceSubmitRestoreAndEnumerations()
        try await testFailureRecoveryAndSpeculativePauseChunk()
        try await testPhase3VoiceMetaCommandsAndSyntax()
        try await testPhase4InjectionAndPillHUD()
        print("ALL PASSED")
    }

    private static func testDelivery() async throws {
        for mode in [DictationMode.toggle, .pushToTalk] {
            let fixture = Fixture()
            fixture.settings.dictationMode = mode
            let editor = ComposerTextView()
            try await fixture.start(into: editor)
            fixture.coordinator.toggle(into: editor)
            try await wait { fixture.models.pending != nil }
            fixture.models.finish("Spoken words")
            try await wait { fixture.coordinator.field == nil }
            expect(editor.string == "Spoken words", "Both shortcut modes insert the field's transcript")
            expect(Paster.copies.isEmpty, "A field mic ignores the copy-only destination setting")
        }
    }

    private static func testScopedCancellation() async throws {
        let fixture = Fixture()
        let editor = ComposerTextView()
        fixture.coordinator.toggle(into: editor)
        fixture.coordinator.cancel(in: editor)
        try await wait { fixture.capture.stopCount > 0 }
        expect(fixture.coordinator.field == nil, "Cancellation covers a recording still starting")
        expect(!fixture.capture.isRecording, "A canceled start cannot leave recording active")

        try await fixture.start(into: editor)
        fixture.coordinator.cancel(in: ComposerTextView())
        expect(fixture.capture.isRecording, "Another editor cannot cancel this session")
        expect(fixture.coordinator.field != nil, "Unrelated teardown preserves the field owner")
        fixture.coordinator.cancel(in: editor)
        try await wait { !fixture.capture.isRecording }
    }

    private static func testChatSwitch() async throws {
        let fixture = Fixture()
        let state = SurfaceState()
        let first = state.chat
        let second = Draft("Second draft")
        let surface = Surface(state: state, dictation: fixture.coordinator)
        defer { surface.close() }
        try await wait { surface.editor != nil }
        let editor = surface.editor!
        try await fixture.start(into: editor)
        fixture.coordinator.accept()
        try await wait { fixture.models.pending != nil }
        state.chat = second
        try await wait { surface.editor?.string == second.text }
        expect(surface.editor === editor, "Chat switching exercises the same reused editor")
        expect(fixture.coordinator.field == nil, "Rebinding cancels the old chat's transcription")
        fixture.models.finish("Late speech for the first chat")
        try await wait { fixture.models.finished }
        await fixture.queue.drain()
        expect(first.text == "First draft", "Canceled transcription leaves the original draft intact")
        expect(second.text == "Second draft", "Canceled transcription cannot enter the new chat")
        expect(fixture.messages.isEmpty, "Destination cancellation does not report an insertion error")
    }

    private static func testWindowClose() async throws {
        let fixture = Fixture()
        let state = SurfaceState()
        let surface = Surface(state: state, dictation: fixture.coordinator)
        try await wait { surface.editor != nil }
        let oldEditor = surface.editor!
        try await fixture.start(into: oldEditor)
        surface.close()
        try await wait { fixture.coordinator.field == nil && !fixture.capture.isRecording }
        expect(!oldEditor.isEditable, "Teardown rejects delayed in-process writes")
        expect(oldEditor.delegate == nil, "Teardown releases the old draft binding")
        expect(oldEditor.onDropFiles == nil, "Teardown releases attachment callbacks")

        let reopened = Surface(state: state, dictation: fixture.coordinator)
        defer { reopened.close() }
        try await wait { reopened.editor != nil }
        expect(reopened.editor !== oldEditor, "Reopening creates a fresh editor")
        try await fixture.start(into: reopened.editor!)
        expect(fixture.capture.isRecording, "The reopened field can start its own recording")
        fixture.coordinator.cancel(in: reopened.editor!)
        try await wait { !fixture.capture.isRecording }
    }

    private static func testQueuedCancellation(closing: Bool) async throws {
        let fixture = Fixture()
        let state = SurfaceState()
        let first = state.chat
        let surface = Surface(state: state, dictation: fixture.coordinator)
        defer { surface.close() }
        try await wait { surface.editor != nil }
        let editor = surface.editor!
        var release: CheckedContinuation<Void, Never>?
        fixture.queue.enqueue(isAutomatic: false) {
            await withCheckedContinuation { release = $0 }
        }
        try await wait { release != nil }
        try await fixture.start(into: editor)
        fixture.coordinator.accept()
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("Already transcribed")
        try await wait { !fixture.panel.isVisible }
        expect(fixture.coordinator.field?.isTranscribing == true, "Queued insertion retains its session")

        if closing {
            surface.close()
        } else {
            state.chat = Draft("New chat")
            try await wait { surface.editor?.string == "New chat" }
        }
        try await wait { fixture.coordinator.field == nil }
        release?.resume()
        await fixture.queue.drain()
        expect(first.text == "First draft", "Queued speech cannot write into its canceled draft")
        expect(state.chat.text == (closing ? "First draft" : "New chat"), "Queued speech cannot cross chats")
        expect(fixture.messages.isEmpty, "Discarding queued speech is silent")
    }

    private static func testSoundsOff() async throws {
        let fixture = Fixture()
        fixture.settings.dictationPlaysSounds = false
        let editor = ComposerTextView()
        AudioEvents.log = []
        fixture.coordinator.toggle(into: editor)
        expect(AudioEvents.log == ["duck"], "Without sounds, ducking still starts at the press")
        try await wait { fixture.capture.isRecording }
        fixture.coordinator.toggle(into: editor)
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("Spoken words")
        try await wait { fixture.coordinator.field == nil }
        expect(
            !AudioEvents.log.contains("start cue") && !AudioEvents.log.contains("stop cue"),
            "No cue plays unless sounds are on")
    }

    private static func testSounds() async throws {
        let fixture = Fixture()
        let editor = ComposerTextView()
        AudioEvents.log = []
        try await fixture.start(into: editor)
        try await Task.sleep(for: .milliseconds(20))
        expect(AudioEvents.log.isEmpty, "The start cue waits for the microphone's first samples")
        fixture.capture.onLevels?([])
        try await wait { AudioEvents.log.contains("duck") }
        expect(
            AudioEvents.log == ["start cue", "duck"],
            "The start cue plays on the first samples, with ducking")
        fixture.coordinator.toggle(into: editor)
        expect(
            AudioEvents.log == ["start cue", "duck", "restore", "stop cue"],
            "The stop cue plays once the volume is restored, before the microphone closes")
        expect(fixture.capture.isRecording, "The microphone is still open when the stop cue plays")
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("Spoken words")
        try await wait { fixture.coordinator.field == nil }
        expect(editor.string == "Spoken words", "Sounds leave the transcript untouched")
    }

    private static func testCancelSilently() async throws {
        let fixture = Fixture()
        let editor = ComposerTextView()
        AudioEvents.log = []
        try await fixture.start(into: editor)
        fixture.capture.onLevels?([])
        try await wait { AudioEvents.log.contains("duck") }
        fixture.coordinator.cancel(in: editor)
        try await wait { !fixture.capture.isRecording }
        try await Task.sleep(for: .milliseconds(50))
        expect(!AudioEvents.log.contains("stop cue"), "Cancelling plays no stop cue")
    }

    private static func testCancelDuringStartCue() async throws {
        let fixture = Fixture()
        let editor = ComposerTextView()
        AudioEvents.log = []
        try await fixture.start(into: editor)
        fixture.capture.isBluetooth = true
        fixture.capture.onLevels?([])
        fixture.coordinator.cancel(in: editor)
        try await Task.sleep(for: .milliseconds(600))
        expect(
            !AudioEvents.log.contains("start cue") && !AudioEvents.log.contains("duck"),
            "A session cancelled before its start cue plays no cue and never ducks")
    }

    private static func testBluetoothStartCue() async throws {
        let fixture = Fixture()
        let editor = ComposerTextView()
        AudioEvents.log = []
        try await fixture.start(into: editor)
        fixture.capture.isBluetooth = true
        let samples = ContinuousClock.now
        fixture.capture.onLevels?([])
        try await wait { AudioEvents.log.contains("start cue") }
        expect(
            ContinuousClock.now - samples >= .milliseconds(500),
            "A Bluetooth microphone delays the start cue until its headset has switched output")
        fixture.coordinator.cancel(in: editor)
    }

    private static func testHoldAndDoubleTapHandsFree() async throws {
        // 1. Hold-key (Fn/Globe) double-tap starts hands-free recording; release ignores stop; single tap stops.
        do {
            let fixture = Fixture()
            fixture.settings.dictationMode = .pushToTalk
            fixture.settings.dictationDoubleTapToLock = true
            fixture.hotKeys.dictationBinding = .init(shortcut: nil, holdKey: 63)

            // Bare single tap while idle does not start push-to-talk recording.
            fixture.coordinator.holdTapped()
            try await Task.sleep(for: .milliseconds(20))
            expect(!fixture.capture.isRecording, "A bare single Fn tap while idle does not start push-to-talk")

            // Double-tap enters hands-free lock and ignores hold release.
            fixture.coordinator.holdDoubleTapped()
            try await wait { fixture.capture.isRecording }
            expect(fixture.coordinator.isHandsFreeLocked, "Double-tap Fn locks hands-free mode")
            fixture.coordinator.released()
            expect(fixture.capture.isRecording, "Release does not stop a hands-free locked session")

            // A subsequent single tap stops hands-free recording and transcribes.
            fixture.coordinator.holdTapped()
            try await wait { fixture.models.pending != nil }
            fixture.models.finish("Hands free transcript")
            try await wait { !fixture.coordinator.isHandsFreeLocked && Paster.copies.last == "Hands free transcript" }
            expect(true, "Single tap cleanly finishes a hands-free session")
        }

        // 2. Rapid combo double-tap locks instead of stopping on the second press.
        do {
            let fixture = Fixture()
            fixture.settings.dictationMode = .pushToTalk
            fixture.settings.dictationDoubleTapToLock = true
            fixture.hotKeys.dictationBinding = .init(shortcut: 49, holdKey: nil)

            fixture.coordinator.pressed()
            fixture.coordinator.released()
            fixture.coordinator.pressed()
            fixture.coordinator.released()
            try await wait { fixture.capture.isRecording }
            expect(fixture.coordinator.isHandsFreeLocked, "Rapid combo double-tap locks hands-free instead of stopping")
            expect(fixture.models.pending == nil, "Locked session keeps recording after second release")
            fixture.coordinator.cancel()
            try await wait { !fixture.capture.isRecording }
        }
    }

    private static func testWisprVoiceSubmitRestoreAndEnumerations() async throws {
        Permissions.accessibilityTrusted = true
        defer { Permissions.accessibilityTrusted = false }

        // 1. Default .paste preserves user clipboard (restorePasteboard == true), formats enumerations,
        //    strips trailing "press enter" and requests Return press after pasting.
        do {
            let fixture = Fixture()
            fixture.settings.dictationMode = .pushToTalk
            fixture.settings.dictationDestination = .paste
            fixture.settings.dictationAutoCopyToClipboard = false
            fixture.settings.dictationVoiceSubmit = true
            fixture.hotKeys.dictationBinding = .init(shortcut: nil, holdKey: 63)

            fixture.coordinator.pressed()
            try await wait { fixture.capture.isRecording }
            fixture.coordinator.released() // Exercises 120ms tail buffer before accept()
            try await wait { fixture.models.pending != nil }
            fixture.models.finish("First buy milk. Second write tests. Press enter.")
            try await wait { Paster.copies.last == "1. Buy milk.\n2. Write tests" }
            expect(Paster.lastRestorePasteboard == true, "Paste-only mode restores prior clipboard")
            expect(Paster.lastPressReturn == true, "Trailing 'Press enter' strips command and submits Return")
        }

        // 2. Auto-copy keeps clipboard (restorePasteboard == false) and negated phrase avoids submit.
        do {
            let fixture = Fixture()
            fixture.settings.dictationMode = .toggle
            fixture.settings.dictationDestination = .paste
            fixture.settings.dictationAutoCopyToClipboard = true
            fixture.settings.dictationVoiceSubmit = true

            fixture.coordinator.pressed()
            try await wait { fixture.capture.isRecording }
            fixture.coordinator.pressed()
            try await wait { fixture.models.pending != nil }
            fixture.models.finish("Don't press enter")
            try await wait {
                Paster.copies.last?
                    .trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare("Don't press enter") == .orderedSame
            }
            expect(Paster.lastRestorePasteboard == false, "Auto-copy skips clipboard restoration")
            expect(Paster.lastPressReturn == false, "Negated 'Don't press enter' does not press Return")
        }

        // 3. Auto-learn inserted span isolation helper handles both suffix and mid-document edits.
        expect(
            DictationCoordinator.extractInsertedSegment(
                baseline: "Topics - Resume",
                updated: "Topics - Resume Saurav works"
            ) == "Saurav works",
            "Auto-learn segment extractor isolates appended pasted span"
        )
        expect(
            DictationCoordinator.extractInsertedSegment(
                baseline: "I met today",
                updated: "I met Saurav Sharma today"
            ) == "Saurav Sharma",
            "Auto-learn segment extractor isolates mid-sentence edited span"
        )
    }

    private static func testFailureRecoveryAndSpeculativePauseChunk() async throws {
        // 1. ASR failure on >= 0.8s speech preserves audio in DictationHistoryStore recovery item.
        do {
            let fixture = Fixture()
            fixture.settings.dictationMode = .toggle
            fixture.coordinator.pressed()
            try await wait { fixture.capture.isRecording }
            fixture.capture.simulatedSamples = [Float](repeating: 0.05, count: 16_000)
            fixture.coordinator.pressed()
            try await wait { fixture.models.pending != nil }
            fixture.models.fail(NSError(domain: "dictation.test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Engine hiccup"]))
            try await wait { fixture.coordinator.historyStore.items.first?.text == "[Dictation Recovery — failed transcription]" }
            await fixture.coordinator.historyStore.flushPendingWrites()
            expect(
                fixture.messages.last?.contains("Audio saved in Dictation History") == true,
                "Failed >=0.8s dictation preserves recovery audio and notifies user"
            )

            // Retry / re-transcribe the recovered history item end-to-end with another model.
            if let recovered = fixture.coordinator.historyStore.items.first(where: {
                $0.text == "[Dictation Recovery — failed transcription]"
            }) {
                fixture.settings.dictationAutoAppRouting = false
                fixture.coordinator.retranscribeHistoryItem(recovered, using: .redux)
                try await wait { fixture.models.pending != nil }
                fixture.models.finish("Recovered transcript successfully.")
                try await wait {
                    fixture.coordinator.historyStore.items.first(where: { $0.id == recovered.id })?.text == "Recovered transcript successfully."
                }
                expect(
                    fixture.coordinator.historyStore.items.first(where: { $0.id == recovered.id })?.text == "Recovered transcript successfully.",
                    "Recovery retry re-transcribes saved audio archive and updates History"
                )
            } else {
                fatalError("Missing recovery item for retry test")
            }
        }

        // 2. Speculative pause chunking stitches pre-transcribed chunk cleanly with release tail.
        do {
            Permissions.accessibilityTrusted = true
            defer { Permissions.accessibilityTrusted = false }
            let fixture = Fixture()
            fixture.settings.dictationMode = .toggle
            fixture.settings.dictationDestination = .paste
            fixture.coordinator.pressed()
            try await wait { fixture.capture.isRecording }
            fixture.capture.onPauseChunk?(56_000, [Float](repeating: 0.05, count: 56_000))
            try await wait { fixture.models.pending != nil }
            fixture.models.finish("Alpha clause.")
            try await wait { !fixture.models.transcribing && fixture.models.finished }
            fixture.models.finished = false
            fixture.capture.simulatedSamples = [Float](repeating: 0.05, count: 72_000)
            fixture.coordinator.pressed()
            try await wait { fixture.models.pending != nil }
            fixture.models.finish("Beta clause.")
            try await wait {
                Paster.copies.last?.trimmingCharacters(in: .whitespaces) == "Alpha clause. Beta clause."
            }
            expect(
                Paster.copies.last?.trimmingCharacters(in: .whitespaces) == "Alpha clause. Beta clause.",
                "Speculative pause chunk stitches seamlessly with final release tail"
            )
            expect(
                fixture.coordinator.lastStageTelemetry != nil,
                "Coordinator records per-stage latency telemetry snapshot"
            )
        }
    }

    private static func testPhase3VoiceMetaCommandsAndSyntax() async throws {
        // Standalone voice meta-command executes in-app without pasting the literal phrase.
        let fixture = Fixture()
        fixture.settings.dictationVoiceCommandsEnabled = true
        let editor = ComposerTextView()
        editor.string = "Hello world"
        try await fixture.start(into: editor)
        fixture.coordinator.toggle(into: editor)
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("Select all.")
        try await wait { fixture.coordinator.field == nil }
        expect(
            fixture.coordinator.lastExecutedVoiceCommand == .selectAll,
            "Standalone 'Select all.' executes voice command rather than pasting literal text"
        )
        expect(
            editor.string == "Hello world",
            "Executed voice meta-command does not overwrite editor contents with command phrase"
        )
    }

    private static func testPhase4InjectionAndPillHUD() async throws {
        // 1. Floating pill appears immediately on keypress before capture finishes; compact & fallback card work cleanly.
        let fixture = Fixture()
        fixture.settings.dictationMode = .toggle
        fixture.settings.dictationDestination = .paste
        fixture.settings.dictationPillPosition = .topNotch
        fixture.settings.dictationCompactPill = true
        fixture.settings.dictationLanguage = "Hindi"
        Permissions.accessibilityTrusted = false

        fixture.coordinator.pressed()
        expect(fixture.panel.isVisible, "Floating HUD pill appears synchronously at 0 ms before capture finishes")
        expect(fixture.panel.state.isCompact, "Panel tracks compact orb preference")
        expect(fixture.panel.state.activeLanguageCode == "HI", "Panel surfaces ISO code badge for active language")

        try await wait { fixture.capture.isRecording }
        fixture.coordinator.pressed()
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("Accessibility fallback phrase")
        try await wait { fixture.panel.state.phase == .fallback }
        expect(
            fixture.panel.isVisible
                && fixture.panel.state.fallbackText == "Accessibility fallback phrase",
            "Untrusted Accessibility pops fallback copy HUD card instead of silently dropping text"
        )

        // 2. Quartz top-left AX bounds convert cleanly to Cocoa bottom-left screen coordinates.
        let converted = DictationInsertionContext.cocoaRect(
            fromQuartzAXRect: CGRect(x: 200, y: 100, width: 2, height: 18),
            primaryScreenHeight: 1080
        )
        expect(
            converted == CGRect(x: 200, y: 962, width: 2, height: 18),
            "AX caret Quartz coordinates convert accurately into Cocoa screen coordinates"
        )
        expect(
            DictationPillPosition.allCases.count == 4,
            "All four floating pill placement modes are registered"
        )

        // 3. Redacted diagnostic bundle exports valid JSON without exposing API keys or transcripts.
        let jsonStr = fixture.coordinator.redactedDiagnosticBundleJSON()
        let jsonObj = try JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any]
        expect(
            jsonObj?["activeModel"] as? String != nil
                && !jsonStr.contains("groqAPIKey")
                && !jsonStr.contains("Accessibility fallback phrase"),
            "Diagnostic export produces valid redacted JSON excluding secrets and transcripts"
        )
    }

    /// The live poll sleeps longer than `wait` allows.
    private static func waitLong(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func wait(
        _ line: Int = #line,
        until condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                fputs("wait timed out at line \(line); copies=\(Paster.copies.suffix(3))\n", stderr)
                throw CocoaError(.coderInvalidValue)
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        print("PASS  \(message)")
    }

    @MainActor
    private final class Fixture {
        let settings = AppSettings()
        let hotKeys = HotKeyManager()
        let models = DictationModelStore()
        let queue = DeliveryQueue()
        var messages: [String] = []
        lazy var coordinator = DictationCoordinator(
            settings: settings, hotKeys: hotKeys, models: models,
            injector: TextInjector(
                clipboardManager: ClipboardManager(), settings: settings, deliveryQueue: queue),
            audioDucker: DictationAudioDucker(), confirmEnable: { false },
            showMessage: { [weak self] message, _ in self?.messages.append(message) })

        var capture: DictationCapture { DictationCapture.latest! }
        var panel: DictationPanelController { DictationPanelController.latest! }

        func start(into editor: ComposerTextView) async throws {
            coordinator.toggle(into: editor)
            try await wait { capture.isRecording }
            expect(coordinator.field?.editor == ObjectIdentifier(editor), "The session belongs to its editor")
        }
    }

    @MainActor
    @Observable
    fileprivate final class Draft {
        let id = UUID()
        var text: String
        init(_ text: String) { self.text = text }
    }

    @MainActor
    @Observable
    fileprivate final class SurfaceState {
        var chat = Draft("First draft")
    }

    private struct Root: View {
        let state: SurfaceState
        let dictation: DictationCoordinator

        var body: some View { Composer(chat: state.chat, dictation: dictation) }
    }

    private struct Composer: View {
        let chat: Draft
        let dictation: DictationCoordinator
        @State private var handle = ComposerTextViewHandle()
        @State private var targeted = false

        var body: some View {
            @Bindable var chat = chat
            ChatComposerTextView(
                text: $chat.text, focusKey: chat.id, maximumTextHeight: 180, handle: handle,
                isFileDragTargeted: $targeted, onDropFiles: { _ in },
                onInvalidate: { dictation.cancel(in: $0) }, onSubmit: {})
        }
    }

    @MainActor
    private final class Surface {
        private var window: NSWindow?

        init(state: SurfaceState, dictation: DictationCoordinator) {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Root(state: state, dictation: dictation))
            window.contentView?.layoutSubtreeIfNeeded()
            self.window = window
        }

        var editor: ComposerTextView? { window?.contentView.flatMap(Self.findEditor) }

        func close() {
            window?.close()
            window = nil
        }

        private static func findEditor(_ view: NSView) -> ComposerTextView? {
            if let editor = view as? ComposerTextView { return editor }
            return view.subviews.lazy.compactMap(findEditor).first
        }
    }
}

@MainActor
final class AppSettings {
    var snippetsEnabled = false
    var dictationEnabled = true
    var dictationMode = DictationMode.toggle
    var dictationModel = DictationModel.redux
    var dictationMicrophone: String?
    var dictationLanguage: String?
    var dictationDestination = DictationDestination.copy
    var dictationAdaptsCapitalization = true
    var dictationLiveInsertion = false
    var dictationPlaysSounds = true
    var dictationOtherAudioMode = DictationOtherAudioMode.lower
    var dictationConvertSpokenEmoji = true
    var dictationSpokenPunctuation = true
    var dictationRemoveFillerWords = false
    var dictationAutoCopyToClipboard = false
    var dictationS1Enabled = false
    var dictationS1Tone = S1Tone.casual
    var dictationS1Structure = S1Structure.prose
    var dictationS1Context = S1Context.general
    var dictationS1IdleRelease = DictationIdleRelease.tenMinutes
    var dictationPasteMode = DictationPasteMode.allAtOnce
    var dictationLivePreviewEnabled = true
    var dictationTranscriptionProvider = DictationTranscriptionProvider.local
    var dictationCloudSpeechProvider = DictationCloudSpeechProvider.groq
    var dictationPolishProvider = DictationPolishProvider.localS1
    var dictationGroqTranscriptionModel = "whisper-large-v3-turbo"
    var dictationDeepgramModel = "nova-3"
    var dictationGroqPolishModel = "openai/gpt-oss-120b"
    var dictationBengaliMode = DictationBengaliMode.off
    var dictationHindiMode = DictationHindiMode.off
    var dictationDoubleTapToLock = true
    var dictationCommandModeEnabled = true
    var dictationAutoAppRouting = true
    var dictationWhisperMode = false
    var dictationAutoLearnDictionary = true
    var dictationVoiceSubmit = true
    var dictationCodeAndMarkdownSyntax = true
    var dictationVoiceCommandsEnabled = true
    var dictationPillPosition = DictationPillPosition.bottomCenter
    var dictationCompactPill = false
    var dictationAudioRetentionDays = 14
    var dictationAutoApplyTransform = false
    var dictationActiveTransformID: String?
    var dictationRetainCancelled = false
    var dictationSpeakerCount = 0
    var dictationVADEnabled = true
    var dictationWarmPreRoll = false
    var dictationVoiceProcessing = false
    var dictationPauseMedia = false
    var dictationMeetingCapturesSystemAudio = true
    var dictationMeetingStartMuted = false
    var dictationAutoStopSilenceSeconds: Double = 0
    var calendarSuggestsMeetingRecording = false
    var groqAPIKey = ""
    var deepgramAPIKey = ""
}

enum HotKeyAction { case dictation, dictationSecondary, dictationAddWord, dictationPasteLast, dictationCopyLast }

@MainActor
final class HotKeyManager {
    struct Binding {
        var shortcut: Int?
        var holdKey: Int?
    }
    var dictationBinding: Binding?
    func binding(for action: HotKeyAction) -> Binding? { action == .dictation ? dictationBinding : nil }
    func conflictOwner(of binding: Binding, excluding action: HotKeyAction) -> String? { nil }
}

@MainActor
final class DictationCapture {
    static weak var latest: DictationCapture?
    var onLevels: (([Float]) -> Void)?
    var onSamples: (@Sendable ([Float]) -> Void)?
    var onPauseChunk: (@Sendable (_ rangeEndSample: Int, _ chunk: [Float]) -> Void)?
    var onLimit: (() -> Void)?
    var onSilenceWarning: ((Bool) -> Void)?
    var onClippingWarning: ((Bool) -> Void)?
    var onClamshellWarning: ((Bool) -> Void)?
    var onAutoStopSilence: (() -> Void)?
    var isRecording = false
    var isMuted = false
    var isBluetooth = false
    var stopCount = 0
    var simulatedSamples: [Float]?

    init() { Self.latest = self }
    func setMuted(_ muted: Bool) { isMuted = muted }
    func configureWarmPreRoll(enabled: Bool, microphoneID: String?, voiceProcessing: Bool = false) {}
    func start(
        microphoneID: String?,
        prioritizedMicrophoneIDs: [String] = [],
        whisperMode: Bool = false,
        allowLongCapture: Bool = false,
        startMuted: Bool = false,
        autoStopSilenceSeconds: TimeInterval = 0,
        voiceProcessing: Bool = false
    ) async throws {
        isMuted = startMuted
        isRecording = true
    }
    var snapshotSamples: [Float] = []
    func snapshot() -> [Float] { snapshotSamples }
    func stop() async -> [Float] {
        isRecording = false
        stopCount += 1
        let out = simulatedSamples ?? [Float](repeating: 0, count: 1_600)
        simulatedSamples = nil
        return out
    }
}

@MainActor
final class DictationModelStore {
    var pending: CheckedContinuation<String, any Error>?
    var finished = false
    var transcribing = false

    func isInstalled(_ model: DictationModel) -> Bool { true }
    func download(_ model: DictationModel) async throws {}
    func delete(_ model: DictationModel) async throws {}
    func prewarm(_ model: DictationModel) {}
    func ensurePrewarmed(_ model: DictationModel) {}
    func stop() async {}
    func prepareForTermination() {}

    func transcribe(_ samples: [Float], model: DictationModel, language: String?) async throws -> String {
        transcribing = true
        defer {
            transcribing = false
            finished = true
        }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func transcribeTimed(
        _ samples: [Float],
        model: DictationModel,
        language: String? = nil,
        useVAD: Bool = true,
        diarizeSpeakers: Int? = nil
    ) async throws -> TimedTranscript {
        let text = try await transcribe(samples, model: model, language: language)
        return TimedTranscript(text: text)
    }

    func finish(_ text: String) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: text)
    }

    func fail(_ error: any Error) {
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: error)
    }
}

@MainActor
final class DictationPanelController {
    enum Phase { case listening, transcribing, completed, fallback }
    @MainActor
    final class State {
        var phase = Phase.listening
        var levels: [Float] = []
        var previewText: String = ""
        var isLockedHandsFree: Bool = false
        var isWhisperMode: Bool = false
        var isMicSilent: Bool = false
        var isClamshellMuffled: Bool = false
        var isMuted: Bool = false
        var isRawMode: Bool = false
        var isSpeechActive: Bool = false
        var isCompact: Bool = false
        var activeLanguageCode: String? = nil
        var commandModeText: String? = nil
        var fallbackText: String? = nil
        var fallbackSubtitle: String? = nil
        var onToggleMute: (() -> Void)?
        var onAccept: (() -> Void)?
        var onCancel: (() -> Void)?
        var onSelectLanguage: ((String?) -> Void)?
        var onCopyFallback: (() -> Void)?
        var onRetryPasteFallback: (() -> Void)?
    }
    static weak var latest: DictationPanelController?
    let state = State()
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?
    var isVisible = false
    init() { Self.latest = self }
    func show(
        position: DictationPillPosition = .bottomCenter,
        compact: Bool = false,
        caretRect: CGRect? = nil,
        activeLanguage: String? = nil
    ) {
        state.isCompact = compact
        state.activeLanguageCode = DictationLanguage.isoCode(for: activeLanguage)?.uppercased()
        isVisible = true
    }
    func showFallbackCard(text: String, subtitle: String) {
        state.fallbackText = text
        state.fallbackSubtitle = subtitle
        state.phase = .fallback
        isVisible = true
    }
    func close() { isVisible = false }
    func showSuccessAndClose() { isVisible = false }
    func updatePreviewText(_ text: String) { state.previewText = text }
}

@MainActor
enum AudioEvents {
    static var log: [String] = []
}

@MainActor
final class DictationAudioDucker {
    func begin(mode: DictationOtherAudioMode = .lower) { AudioEvents.log.append("duck") }
    func end(mode: DictationOtherAudioMode = .lower) { AudioEvents.log.append("fade up") }
    func restoreImmediately() { AudioEvents.log.append("restore") }
}

@MainActor
final class DictationCueRunner {
    enum Cue { case start, stop }

    func play(_ cue: Cue) { AudioEvents.log.append(cue == .start ? "start cue" : "stop cue") }
}

@MainActor
final class ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.sauravsz.szcast.internal")
    func prepareForSzcastPasteboardMutation() {}
    func synchronizeAfterSzcastPasteboardMutation(changeCount: Int) {}
    func pauseCapture() {}
    func resumeCapture() {}
}

@MainActor
enum Permissions {
    static var accessibilityTrusted = false
    @discardableResult
    static func ensureAccessibility() -> Bool { accessibilityTrusted }
    static func isAccessibilityTrusted() -> Bool { accessibilityTrusted }
}

@MainActor
enum Paster {
    static let szcastEventTag: Int64 = 0x54494E59
    static var copies: [String] = []
    static var lastRestorePasteboard = false
    static var lastPressReturn = false
    @MainActor
    static func pasteString(
        _ text: String,
        previousApp: NSRunningApplication?,
        concealed: Bool = false,
        restorePasteboard: Bool = false,
        pressReturnAfter: Bool = false,
        plainTextOnly: Bool = false,
        completion: (@MainActor () -> Void)? = nil
    ) {
        copies.append(text)
        lastRestorePasteboard = restorePasteboard
        lastPressReturn = pressReturnAfter
        completion?()
    }
    @MainActor static func copyPlainText(_ text: String, plainTextOnly: Bool = false) { copies.append(text) }
    @MainActor static func copyConcealedText(_ text: String) { copies.append(text) }
    @MainActor static func postCommandV(toPid pid: pid_t? = nil) {}
    @MainActor static func postCommandC(toPid pid: pid_t? = nil) {}
    @MainActor static func postCommandCharacter(_ character: Character, fallback: CGKeyCode, toPid pid: pid_t? = nil) {}
}

enum DialogTone { case neutral, success, danger }
