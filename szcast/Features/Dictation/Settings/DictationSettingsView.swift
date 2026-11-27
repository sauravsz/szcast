import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

enum DictationSettingsSection: String, CaseIterable, Identifiable {
    case insights = "Insights"
    case general = "General"
    case formatting = "Format & AI"
    case modelLibrary = "Model Library"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case history = "History"

    var id: Self { self }

    var title: String {
        switch self {
        case .modelLibrary: return String(localized: "Model Library")
        default: return rawValue
        }
    }
}

struct DictationSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(SettingsNavigationState.self) private var navigation
    @State private var selectedSection: DictationSettingsSection = .insights
    @State private var microphones: [AVCaptureDevice] = []
    @State private var microphoneAccess = Permissions.microphoneAccess()

    // Dictionary sheet states
    @State private var showingAddWordSheet = false
    @State private var showingImportSheet = false
    @State private var newWordCanonical = ""
    @State private var newWordAliases = ""
    @State private var newWordCategory = "general"
    @State private var importPasteText = ""

    // Snippets state
    @State private var showingAddSnippetSheet = false
    @State private var newSnippetKeyword = ""
    @State private var newSnippetExpansion = ""

    private var snippets: [DictationSnippet] {
        coordinator.dictionaryStore.snippets
    }

    // History search
    @State private var historySearchQuery = ""

    private var dictationPresetBinding: Binding<DictationHotkeyPreset> {
        Binding(
            get: {
                DictationHotkeyPreset.preset(for: hotKeys.binding(for: .dictation))
            },
            set: { newPreset in
                if let binding = newPreset.binding {
                    hotKeys.setBinding(binding, for: .dictation)
                } else {
                    hotKeys.recordingAction = .dictation
                }
            }
        )
    }

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 0) {
            Picker("", selection: $selectedSection) {
                ForEach(DictationSettingsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, Theme.Spacing.md)

            Divider()

            if selectedSection == .insights {
                DictationInsightsDashboardView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if selectedSection == .modelLibrary {
                ModelLibrarySettingsView()
            } else {
                Form {
                    switch selectedSection {
                    case .insights, .modelLibrary:
                        EmptyView()
                    case .general:
                        generalSection(settings: settings)
                    case .formatting:
                        formattingSection(settings: settings)
                    case .dictionary:
                        dictionarySection(settings: settings)
                    case .snippets:
                        snippetsSection(settings: settings)
                    case .history:
                        historySection(settings: settings)
                    }
                }
                .formStyle(.grouped)
            }
        }
        .settingsScrollTarget(.dictation)
        .onAppear {
            syncSectionForScrollRequest(navigation.scrollRequest)
            microphoneAccess = Permissions.microphoneAccess()
            if settings.dictationEnabled { microphones = DictationCapture.microphones }
        }
        .onChange(of: navigation.scrollRequest) { _, request in
            syncSectionForScrollRequest(request)
        }
        .onChange(of: settings.dictationEnabled) { _, enabled in
            if enabled { microphones = DictationCapture.microphones }
            coordinator.syncCapturePreferences()
        }
        .onChange(of: settings.dictationWarmPreRoll) { _, _ in
            coordinator.syncCapturePreferences()
        }
        .onChange(of: settings.dictationMicrophone) { _, _ in
            coordinator.syncCapturePreferences()
        }
        .onChange(of: settings.dictationVoiceProcessing) { _, _ in
            coordinator.syncCapturePreferences()
        }
        .onChange(of: settings.dictationAudioRetentionDays) { _, _ in
            coordinator.applyAudioRetentionPolicy()
        }
        .onChange(of: historySearchQuery) { _, query in
            coordinator.historyStore.refreshItems(query: query)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification)
            {
                microphoneAccess = Permissions.microphoneAccess()
                if settings.dictationEnabled { microphones = DictationCapture.microphones }
            }
        }
        .sheet(isPresented: $showingAddWordSheet) {
            addWordSheet
        }
        .sheet(isPresented: $showingImportSheet) {
            importWordsSheet
        }
        .sheet(isPresented: $showingAddSnippetSheet) {
            addSnippetSheet
        }
    }

    private func syncSectionForScrollRequest(_ request: SettingsScrollRequest?) {
        guard let anchor = request?.target.anchor else { return }
        switch anchor {
        case .modelLibrarySpeech, .modelLibraryPolish, .modelLibraryAudioTools, .modelLibraryAIModels:
            selectedSection = .modelLibrary
        case .dictationDictation, .dictationCommands:
            selectedSection = .general
        case .dictationOutput:
            selectedSection = .formatting
        default:
            break
        }
    }

    // MARK: - General Section

    @ViewBuilder
    private func generalSection(settings: AppSettings) -> some View {
        @Bindable var bSettings = settings

        Section {
            Toggle(isOn: enabledBinding) {
                SettingsFeatureToggleLabel(
                    anchor: .dictationDictation, title: "Enable Dictation",
                    subtitle: "Transcribe speech on your Mac with a local model.")
            }
            if microphoneAccess != .authorized {
                HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .frame(width: SettingsListMetrics.iconSize)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Microphone access required")
                            .foregroundStyle(.orange)
                        Text("Needed to record your dictation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Theme.Spacing.lg)
                    Button(microphoneAccess == .notDetermined ? "Grant Access…" : "Open System Settings") {
                        if microphoneAccess == .notDetermined {
                            Task {
                                _ = await Permissions.requestMicrophoneAccess()
                                microphoneAccess = Permissions.microphoneAccess()
                            }
                        } else {
                            Permissions.openMicrophoneSettings()
                        }
                    }
                }
            }
        }
        .settingsAnchor(.dictationDictation)

        if settings.dictationEnabled {
            dictationHealthInspectorSection(settings: settings)

            Section {
                Picker(selection: microphoneBinding) {
                    Text(microphones.isEmpty ? "No microphone available" : "System default").tag("")
                    if !microphones.isEmpty { Divider() }
                    ForEach(microphones, id: \.uniqueID) { microphone in
                        Text(microphone.localizedName).tag(microphone.uniqueID)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "Input device")
                    Text("Choose the microphone used for recording.")
                }

                Picker(selection: $bSettings.dictationMode) {
                    ForEach(DictationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    SettingsRowTitle(.dictationCommands, "Recording mode")
                    Text("Hold to talk, or press once to start and again to stop.")
                }

                Toggle(isOn: $bSettings.dictationDoubleTapToLock) {
                    SettingsRowTitle(.dictationCommands, "Double-tap to lock hands-free")
                    Text("Rapidly double-tap the shortcut to record continuously without holding the key.")
                }
                .disabled(settings.dictationMode == .toggle)

                Toggle(isOn: $bSettings.dictationWhisperMode) {
                    SettingsRowTitle(.dictationOutput, "Whisper mode")
                    Text("Boosts microphone sensitivity for soft, sub-vocal whispered speech in quiet rooms.")
                }

                Toggle(isOn: $bSettings.dictationWarmPreRoll) {
                    SettingsRowTitle(.dictationOutput, "Instant mic pre-roll (350ms)")
                    Text("Keeps a lightweight ring buffer armed so the first syllable never clips. (Shows mic indicator when enabled.)")
                }

                Toggle(isOn: $bSettings.dictationVoiceProcessing) {
                    SettingsRowTitle(.dictationOutput, "Voice isolation & echo cancellation")
                    Text("Uses Apple Voice Processing DSP on built-in and USB mics to reject speakers and fan noise.")
                }

                Toggle(isOn: $bSettings.dictationPauseMedia) {
                    SettingsRowTitle(.dictationOutput, "Pause media automatically")
                    Text("Pauses Apple Music, Spotify, and browser/video Now-Playing audio while dictating, then resumes.")
                }

                Picker(selection: dictationPresetBinding) {
                    ForEach(DictationHotkeyPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                } label: {
                    SettingsRowTitle(.dictationCommands, "Shortcut")
                    Text(dictationPresetBinding.wrappedValue.summary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Spacing.xs) {
                            SettingsRowTitle(.dictationCommands, dictationPresetBinding.wrappedValue == .custom ? "Custom Hotkey" : "Assigned Key")
                            if coordinator.holdShortcutIssue != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                        }
                        if let issue = coordinator.holdShortcutIssue {
                            Text(issue)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Click to record any custom hotkey or modifier.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    ShortcutRecorder(action: .dictation)
                }

                HStack(spacing: Theme.Spacing.xs) {
                    Text("Presets:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        hotKeys.setBinding(DictationHotkeyPreset.fn.binding, for: .dictation)
                    } label: {
                        Text("Fn key")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(dictationPresetBinding.wrappedValue == .fn ? .accentColor : .secondary)

                    Button {
                        hotKeys.setBinding(DictationHotkeyPreset.optionSpace.binding, for: .dictation)
                    } label: {
                        Text("⌥Space")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(dictationPresetBinding.wrappedValue == .optionSpace ? .accentColor : .secondary)

                    Button {
                        hotKeys.setBinding(DictationHotkeyPreset.controlSpace.binding, for: .dictation)
                    } label: {
                        Text("⌃Space")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(dictationPresetBinding.wrappedValue == .controlSpace ? .accentColor : .secondary)

                    Button {
                        hotKeys.recordingAction = .dictation
                    } label: {
                        Text("Record custom…")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(dictationPresetBinding.wrappedValue == .custom ? .accentColor : .secondary)
                }

                Text("Press Escape anytime to cancel an active recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $bSettings.dictationPlaysSounds) {
                    SettingsRowTitle(.dictationCommands, "Play sounds")
                    Text("Play a sound when recording starts and stops.")
                }

                Picker(selection: $bSettings.dictationPillPosition) {
                    ForEach(DictationPillPosition.allCases) { pos in
                        Text(pos.title).tag(pos)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "Floating pill placement")
                    Text("Choose where the live listening capsule appears on your screen.")
                }
                .accessibilityLabel("Floating pill placement")

                Toggle(isOn: $bSettings.dictationCompactPill) {
                    SettingsRowTitle(.dictationOutput, "Compact orb pill")
                    Text("Shows a minimal floating waveform orb instead of a wide live-preview bar.")
                }
                .accessibilityLabel("Compact orb pill")
            } header: {
                SettingsSectionHeader(.dictationCommands)
            }

            Section {
                Picker(selection: $bSettings.dictationOtherAudioMode) {
                    ForEach(DictationOtherAudioMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "Media during dictation")
                    Text(settings.dictationOtherAudioMode.summary)
                }

                Picker(selection: $bSettings.dictationDestination) {
                    ForEach(DictationDestination.allCases) { destination in
                        Text(destination.title).tag(destination)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "When finished")
                }

                Picker(selection: $bSettings.dictationPasteMode) {
                    ForEach(DictationPasteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "Pasting method")
                    Text(settings.dictationPasteMode.summary)
                }

                Toggle(isOn: $bSettings.dictationAutoCopyToClipboard) {
                    SettingsRowTitle(.dictationOutput, "Auto-copy to clipboard")
                    Text("Copies dictation when automatic pasting is skipped or unavailable.")
                }
            } header: {
                SettingsSectionHeader(.dictationOutput)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add selected word to Dictionary")
                        Text("Select a misheard word in any app, then press these keys.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(action: .dictationAddWord)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paste last dictation")
                        Text("Pastes your most recent transcription.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(action: .dictationPasteLast)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copy last dictation")
                        Text("Copies your most recent transcription to clipboard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(action: .dictationCopyLast)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        SettingsRowTitle(.dictationCommands, "Secondary dictation (Raw mode)")
                        Text("Records literal verbatim text bypassing AI polish.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(action: .dictationSecondary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Switch transcription model")
                        Text("Opens a quick picker for downloaded local and configured cloud models.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(action: .command(.switchTranscriptionModel))
                }

                Toggle(isOn: $bSettings.dictationRetainCancelled) {
                    SettingsRowTitle(.dictationCommands, "Retain cancelled dictations")
                    Text("Transcribes and saves cancelled (Esc) recordings to history instead of discarding.")
                }
            } header: {
                Text("Dictation Shortcuts")
            }

            livePreviewSection(settings: settings)
            audioIntelligenceAndCLISection(settings: settings)
        }
    }

    @ViewBuilder
    private func audioIntelligenceAndCLISection(settings: AppSettings) -> some View {
        @Bindable var bSettings = settings
        Section {
            Toggle(isOn: $bSettings.dictationVADEnabled) {
                SettingsRowTitle(.dictationOutput, "Voice activity detection (VAD)")
                Text("Skips long silence via CoreML Silero VAD before ASR decoding.")
            }

            Picker(selection: $bSettings.dictationSpeakerCount) {
                Text("Auto detect speakers").tag(0)
                ForEach(1...12, id: \.self) { count in
                    Text("\(count) Speaker\(count == 1 ? "" : "s")").tag(count)
                }
            } label: {
                SettingsRowTitle(.dictationOutput, "Speaker diarization")
                Text("Segments multi-speaker files and remote meeting participants offline.")
            }

            Toggle(isOn: $bSettings.dictationMeetingCapturesSystemAudio) {
                SettingsRowTitle(.dictationOutput, "Capture system audio in meetings")
                Text("Uses macOS Process Tap (no Screen Recording permission) for remote \"Others\" track.")
            }

            Toggle(isOn: $bSettings.dictationMeetingStartMuted) {
                SettingsRowTitle(.dictationOutput, "Start meetings muted")
                Text("Starts Meeting Notetaker with microphone muted so only system audio records until unmuted.")
            }

            Picker(selection: $bSettings.dictationAutoStopSilenceSeconds) {
                Text("Off").tag(0.0)
                Text("30 seconds").tag(30.0)
                Text("60 seconds").tag(60.0)
                Text("2 minutes").tag(120.0)
            } label: {
                SettingsRowTitle(.dictationOutput, "Auto-stop on prolonged silence")
                Text("Automatically ends forgotten recordings after continuous silence.")
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    SettingsRowTitle(.dictationCommands, "Transcript Studio & CLI")
                    Text(
                        CLIToolInstaller.installedURL.map { "szcast-cli installed at \($0.path)" }
                            ?? "Install szcast-cli into PATH for terminal transcription and 8-format export."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Studio…") {
                    AppCore.shared.transcriptStudio.showWindow()
                }
                .controlSize(.small)
                if CLIToolInstaller.installedURL == nil {
                    Button("Install CLI") {
                        _ = try? CLIToolInstaller.install()
                    }
                    .controlSize(.small)
                } else {
                    Button("Uninstall CLI") {
                        CLIToolInstaller.uninstall()
                    }
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Long Audio, Diarization & CLI")
        }
    }

    // MARK: - Live Preview Section

    @ViewBuilder
    private func livePreviewSection(settings: AppSettings) -> some View {
        @Bindable var bSettings = settings

        Section {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Show words while you speak")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .help("Displays real-time partial transcription inside the floating recording pill.")

                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)

                        Text("Ready")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                    }

                    Text("See words before you finish your dictation.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: Theme.Spacing.md)

                // Language mode badge/selector
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Automatic")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Auto · no language pinned ⇅")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.Colors.border.opacity(0.4), lineWidth: 1)
                )

                Toggle("", isOn: $bSettings.dictationLivePreviewEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("LIVE PREVIEW")
                Spacer()
                Text("Runs on this Mac. Nothing you say is sent anywhere.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }

        Section {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Image(systemName: "globe")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Universal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Uses on-device Apple Speech framework for live words.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: Theme.Spacing.md)

                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                Text("Ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)

                Menu {
                    Button("Automatic (System Default)") {}
                    Button("English (US)") {}
                    Button("English (UK)") {}
                } label: {
                    Text("Change")
                        .font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderedButton)
                .fixedSize()
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("PREVIEW ENGINE")
                Spacer()
                Text("Compare engines ↗")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private func dictationHealthInspectorSection(settings: AppSettings) -> some View {
        let axTrusted = Permissions.isAccessibilityTrusted()
        let activeModelInstalled = settings.dictationTranscriptionProvider == .cloud
            || coordinator.models.isInstalled(settings.dictationModel)

        Section {
            healthStatusRow(
                title: "Microphone permission",
                detail: microphoneAccess == .authorized
                    ? (settings.dictationMicrophone ?? "System default ready")
                    : "Allow microphone access for voice capture",
                isHealthy: microphoneAccess == .authorized,
                actionTitle: microphoneAccess == .authorized ? nil : "Grant…"
            ) {
                if microphoneAccess == .notDetermined {
                    Task {
                        _ = await Permissions.requestMicrophoneAccess()
                        microphoneAccess = Permissions.microphoneAccess()
                    }
                } else {
                    Permissions.openMicrophoneSettings()
                }
            }

            healthStatusRow(
                title: "Accessibility & direct paste",
                detail: axTrusted
                    ? "Direct AX insertion & auto-paste enabled"
                    : "Needed for auto-paste (otherwise copied cleanly)",
                isHealthy: axTrusted,
                actionTitle: axTrusted ? nil : "Open Settings"
            ) {
                Permissions.openAccessibilitySettings()
            }

            healthStatusRow(
                title: "Hotkey & Fn/Globe readiness",
                detail: coordinator.holdShortcutIssue ?? dictationPresetBinding.wrappedValue.summary,
                isHealthy: coordinator.holdShortcutIssue == nil,
                actionTitle: nil
            ) {}

            healthStatusRow(
                title: "Speech & AI readiness",
                detail: activeModelInstalled
                    ? "\(settings.dictationModel.title) ready"
                    : "Download selected speech model in Model Library",
                isHealthy: activeModelInstalled,
                actionTitle: activeModelInstalled ? nil : "Model Library"
            ) {
                selectedSection = .modelLibrary
            }

            DisclosureGroup("Last Take Telemetry & Diagnostics") {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if let telemetry = coordinator.lastStageTelemetry {
                        Text(telemetry.summaryLine)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Complete one dictation take to record stage latencies.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Copy Redacted Diagnostics") {
                            Paster.copyPlainText(coordinator.redactedDiagnosticBundleJSON(), plainTextOnly: true)
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Copy redacted dictation diagnostics JSON")
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }
        } header: {
            Text("Dictation Health Inspector")
        }
    }

    @ViewBuilder
    private func healthStatusRow(
        title: String,
        detail: String,
        isHealthy: Bool,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isHealthy ? Color.green : Color.orange)
                .font(.system(size: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.md)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .accessibilityLabel("\(title): \(actionTitle)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
    }

    // MARK: - Formatting & AI Polish Section

    @ViewBuilder
    private func formattingSection(settings: AppSettings) -> some View {
        @Bindable var bSettings = settings

        Section {
            Toggle(isOn: $bSettings.dictationConvertSpokenEmoji) {
                SettingsRowTitle(.dictationOutput, "Convert spoken emoji")
                Text("Say a phrase followed by emoji to get its symbol (e.g. \"thumbs up emoji\" → 👍).")
            }

            Toggle(isOn: $bSettings.dictationSpokenPunctuation) {
                SettingsRowTitle(.dictationOutput, "Spoken punctuation")
                Text("Say comma, period, or new paragraph to insert it.")
            }

            Toggle(isOn: $bSettings.dictationRemoveFillerWords) {
                SettingsRowTitle(.dictationOutput, "Remove filler words")
                Text("Strips common filler words (um, uh, hmm, mhm...) from transcriptions.")
            }

            Toggle(isOn: $bSettings.dictationAdaptsCapitalization) {
                SettingsRowTitle(.dictationOutput, "Smart insertion")
                Text("Fits text to the spacing and capitals around your cursor.")
            }

            Toggle(isOn: $bSettings.dictationAutoAppRouting) {
                SettingsRowTitle(.dictationOutput, "Context-aware app styles")
                Text("Adapts tone to active app (casual in Slack/Messages, formal in Mail, syntax-aware in code editors).")
            }

            Toggle(isOn: $bSettings.dictationCommandModeEnabled) {
                SettingsRowTitle(.dictationOutput, "Command mode (Voice edit)")
                Text("Highlight text in any app and speak an instruction to rewrite, translate, or summarize in place.")
            }

            Toggle(isOn: $bSettings.dictationAutoLearnDictionary) {
                SettingsRowTitle(.dictationOutput, "Auto-learn corrections")
                Text("Automatically learns spelling corrections and vocabulary from your post-dictation edits.")
            }
            .onChange(of: settings.dictationAutoLearnDictionary) { _, enabled in
                coordinator.dictionaryStore.selfLearningEnabled = enabled
            }

            Toggle(isOn: $bSettings.dictationVoiceSubmit) {
                SettingsRowTitle(.dictationOutput, "Voice submit (“Press enter”)")
                Text("Automatically presses Return after pasting when you end a dictation with “press enter” or “send message”.")
            }

            Toggle(isOn: $bSettings.dictationCodeAndMarkdownSyntax) {
                SettingsRowTitle(.dictationOutput, "Code casing & Markdown syntax")
                Text("Formats spoken camelCase, snake_case, flags, arrows, headings, tasks, and [[wikilinks]] in code and notes apps.")
            }

            Toggle(isOn: $bSettings.dictationVoiceCommandsEnabled) {
                SettingsRowTitle(.dictationOutput, "Voice control & Ask AI commands")
                Text("Supports standalone commands (“undo that”, “select all”, “copy that”, “new tab”) and “ask AI …” queries.")
            }
        } header: {
            Text("Formatting & Rules")
        }

        Section {
            Toggle(isOn: $bSettings.dictationAutoApplyTransform) {
                SettingsRowTitle(.dictationOutput, "Auto-apply transform")
                Text("Applies your selected AI transform prompt to speech before insertion.")
            }

            if settings.dictationAutoApplyTransform {
                Picker(selection: Binding(
                    get: { settings.dictationActiveTransformID ?? DictationTransform.bulletPoints.id.uuidString },
                    set: { settings.dictationActiveTransformID = $0 }
                )) {
                    ForEach(coordinator.transformStore.allTransforms) { transform in
                        Text(transform.name).tag(transform.id.uuidString)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "Active transform")
                    Text("Choose structured AI prompt applied to your dictation.")
                }
            }
        } header: {
            Text("Transforms (Custom Prompts)")
        }

        Section {
            Toggle(isOn: $bSettings.dictationS1Enabled) {
                SettingsRowTitle(.dictationOutput, "Enable AI Polish (S1-mini)")
                Text("Clean up and format transcriptions with on-device S1-mini AI normalization.")
            }

            if settings.dictationS1Enabled {
                Picker(selection: $bSettings.dictationS1Tone) {
                    ForEach(S1Tone.allCases) { tone in
                        Text(tone.title).tag(tone)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "Tone")
                    Text("Choose how formal your text sounds.")
                }

                Picker(selection: $bSettings.dictationS1Structure) {
                    ForEach(S1Structure.allCases) { structure in
                        Text(structure.title).tag(structure)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "Structure")
                    Text("Keep sentences or turn spoken items into prose or lists.")
                }

                Picker(selection: $bSettings.dictationS1Context) {
                    ForEach(S1Context.allCases) { ctx in
                        Text(ctx.title).tag(ctx)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "Context")
                    Text("Format dictated greetings and sign-offs as email or general prose.")
                }

                Picker(selection: $bSettings.dictationBengaliMode) {
                    ForEach(DictationBengaliMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "Bengali Romanization (Banglish)")
                    Text(settings.dictationBengaliMode.summary)
                }
                .onChange(of: settings.dictationBengaliMode) { _, newValue in
                    if newValue == .indicFlex { coordinator.activateLocalModel(.indicFlex) }
                }

                Picker(selection: $bSettings.dictationHindiMode) {
                    ForEach(DictationHindiMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    SettingsRowTitle(.dictationOutput, "Hindi Romanization (Hinglish)")
                    Text(settings.dictationHindiMode.summary)
                }
                .onChange(of: settings.dictationHindiMode) { _, newValue in
                    if newValue == .whisperApex { coordinator.activateLocalModel(.whisperApex) }
                }
            }
        } header: {
            Text("AI Polish (S1-mini)")
        }
    }

    // MARK: - Dictionary & Vocabulary Packs Section

    @ViewBuilder
    private func dictionarySection(settings: AppSettings) -> some View {
        Section {
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    newWordCanonical = ""
                    newWordAliases = ""
                    newWordCategory = "general"
                    showingAddWordSheet = true
                } label: {
                    Label("Add word", systemImage: "plus")
                }

                Button {
                    importPasteText = ""
                    showingImportSheet = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                Button {
                    exportWords()
                } label: {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                }

                Button {
                    exportWordsPlainText()
                } label: {
                    Label("Export .txt", systemImage: "doc.plaintext")
                }

                Spacer()
            }
            .buttonStyle(.bordered)
        } header: {
            Text("Your Words (\(coordinator.dictionaryStore.words.count))")
        }

        Section {
            Toggle(isOn: Binding(
                get: { coordinator.dictionaryStore.selfLearningEnabled },
                set: { coordinator.dictionaryStore.selfLearningEnabled = $0 }
            )) {
                SettingsRowTitle(.dictationOutput, "Self-Learning Dictionary")
                Text("Automatically detects when you correct a dictation and adds the corrected word.")
            }
        } header: {
            Text("Learn From…")
        }

        Section {
            ForEach(VocabularyPackType.allCases) { pack in
                let isEnabled = coordinator.dictionaryStore.enabledPacks.contains(pack)
                Toggle(isOn: Binding(
                    get: { isEnabled },
                    set: { enabled in
                        if enabled {
                            coordinator.dictionaryStore.enabledPacks.insert(pack)
                        } else {
                            coordinator.dictionaryStore.enabledPacks.remove(pack)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(pack.displayName)
                                .fontWeight(.medium)
                            Text("· \(pack.fixesCount) fixes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(pack.blurb + " e.g. " + pack.examples)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Vocabulary Packs")
        } footer: {
            Text("Ready-made word lists for a field. Turn one on and szcast starts fixing words it gets wrong.")
        }

        if !coordinator.dictionaryStore.words.isEmpty {
            Section {
                ForEach(coordinator.dictionaryStore.words) { word in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(word.canonical)
                                    .fontWeight(.medium)
                                if word.isAutoLearned {
                                    Image(systemName: "sparkles")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                }
                                Text("[\(word.category)]")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !word.aliases.isEmpty {
                                Text("Aliases: " + word.aliases.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            coordinator.dictionaryStore.removeWord(id: word.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Custom Terms")
            }
        }
    }

    // MARK: - Snippets Section

    @ViewBuilder
    private func snippetsSection(settings: AppSettings) -> some View {
        Section {
            HStack {
                Button {
                    newSnippetKeyword = ""
                    newSnippetExpansion = ""
                    showingAddSnippetSheet = true
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        } header: {
            Text("Dictation Snippets")
        } footer: {
            Text("Say a snippet's trigger keyword during dictation to expand it automatically.")
        }

        if !snippets.isEmpty {
            Section {
                ForEach(snippets) { snippet in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snippet.keyword)
                                .fontWeight(.medium)
                            Text(snippet.expansion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            deleteSnippet(snippet.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Saved Snippets (\(snippets.count))")
            }
        }
    }

    // MARK: - History Section

    @ViewBuilder
    private func historySection(settings: AppSettings) -> some View {
        @Bindable var bSettings = settings

        Section {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history…", text: $historySearchQuery)
                    .textFieldStyle(.plain)
                if !historySearchQuery.isEmpty {
                    Button { historySearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Picker(selection: $bSettings.dictationAudioRetentionDays) {
                Text("Text only (delete audio immediately)").tag(0)
                Text("Keep audio for 7 days").tag(7)
                Text("Keep audio for 14 days").tag(14)
                Text("Keep audio for 30 days").tag(30)
            } label: {
                SettingsRowTitle(.dictationOutput, "Audio archive retention")
                Text("Controls how long compressed .m4a recordings remain stored for replay and re-transcription.")
            }
        }

        let filteredItems = coordinator.historyStore.items

        if !filteredItems.isEmpty {
            Section {
                ForEach(filteredItems) { item in
                    let isRecovery = item.text.hasPrefix("[Dictation Recovery")
                    let hasAudio = coordinator.historyStore.audioURL(for: item) != nil
                    let isPlaying = coordinator.historyStore.playingItemID == item.id

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            if isRecovery {
                                Label("Recovery", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("· \(item.wordCount) words")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()

                            if hasAudio {
                                Button {
                                    coordinator.historyStore.toggleAudioPlayback(for: item)
                                } label: {
                                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                                        .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help(isPlaying ? "Stop audio" : "Play recording")

                                if isRecovery {
                                    Button("Retry") {
                                        coordinator.retranscribeHistoryItem(item)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.mini)
                                } else {
                                    Menu {
                                        ForEach(DictationModel.allCases.filter { coordinator.models.isInstalled($0) }) { m in
                                            Button(m.title) {
                                                coordinator.retranscribeHistoryItem(item, using: m)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                    .help("Re-transcribe with another model")
                                }
                            }

                            Button {
                                Paster.copyPlainText(item.text)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy to clipboard")

                            Button {
                                coordinator.pasteHistoryItem(item.text)
                            } label: {
                                Image(systemName: "arrow.right.doc.on.clipboard")
                            }
                            .buttonStyle(.borderless)
                            .help("Paste into frontmost app")

                            Button(role: .destructive) {
                                coordinator.historyStore.delete(id: item.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        Text(item.text)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, Theme.Spacing.xxs)
                }
                if coordinator.historyStore.hasMoreItems {
                    HStack {
                        Spacer()
                        Button("Load Older Dictations") {
                            coordinator.historyStore.loadMore()
                        }
                        .controlSize(.small)
                        Spacer()
                    }
                }
            } header: {
                HStack {
                    Text("History (\(filteredItems.count))")
                    Spacer()
                    Button("Clear All", role: .destructive) {
                        coordinator.historyStore.clearAll()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .font(.caption)
                }
            }
        } else {
            Section {
                Text("No dictations recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sheets

    private var addWordSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Add Word to Dictionary")
                .font(.headline)

            TextField("Canonical Word (e.g. AngularJS)", text: $newWordCanonical)
                .textFieldStyle(.roundedBorder)

            TextField("Aliases comma-separated (e.g. angularge, ingiolarge)", text: $newWordAliases)
                .textFieldStyle(.roundedBorder)

            Picker("Category", selection: $newWordCategory) {
                Text("General").tag("general")
                Text("Tech").tag("tech")
                Text("Brand").tag("brand")
                Text("Name").tag("name")
            }

            HStack {
                Spacer()
                Button("Cancel") { showingAddWordSheet = false }
                Button("Save") {
                    let aliases = newWordAliases.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    coordinator.dictionaryStore.addWord(canonical: newWordCanonical, aliases: aliases, category: newWordCategory)
                    showingAddWordSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newWordCanonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private var importWordsSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Import Words")
                .font(.headline)
            Text("Bring your words in from anywhere. Nothing is added until you review it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $importPasteText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Button("Open a File…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.json, .plainText, .commaSeparatedText]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        _ = try? coordinator.dictionaryStore.importFromFile(at: url)
                        showingImportSheet = false
                    }
                }
                Spacer()
                Button("Cancel") { showingImportSheet = false }
                Button("Import") {
                    _ = coordinator.dictionaryStore.importFromText(importPasteText)
                    showingImportSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(importPasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 450)
    }

    private var addSnippetSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Add Dictation Snippet")
                .font(.headline)

            TextField("Spoken Keyword (e.g. my email)", text: $newSnippetKeyword)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $newSnippetExpansion)
                .font(.body)
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Spacer()
                Button("Cancel") { showingAddSnippetSheet = false }
                Button("Save") {
                    addSnippet(keyword: newSnippetKeyword, expansion: newSnippetExpansion)
                    showingAddSnippetSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newSnippetKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func exportWords() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "szcast Words.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? coordinator.dictionaryStore.exportToJSON(to: url)
        }
    }

    private func exportWordsPlainText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "szcast Hotwords.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? coordinator.dictionaryStore.exportToPlainText(to: url)
        }
    }

    // MARK: - Snippet operations

    private func addSnippet(keyword: String, expansion: String) {
        coordinator.dictionaryStore.addSnippet(keyword: keyword, expansion: expansion)
    }

    private func deleteSnippet(_ id: UUID) {
        coordinator.dictionaryStore.deleteSnippet(id)
    }

    // MARK: - Bindings & Helpers

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.dictationEnabled },
            set: { coordinator.setEnabled($0) })
    }

    private var microphoneBinding: Binding<String> {
        Binding(
            get: { settings.dictationMicrophone ?? "" },
            set: { settings.dictationMicrophone = $0.isEmpty ? nil : $0 })
    }
}
