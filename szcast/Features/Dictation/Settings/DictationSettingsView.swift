import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

enum DictationSettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case formatting = "Formatting & AI"
    case dictionary = "Dictionary & Packs"
    case snippets = "Snippets"
    case history = "History"

    var id: Self { self }
}

struct DictationSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyManager.self) private var hotKeys
    @State private var selectedSection: DictationSettingsSection = .general
    @State private var microphones: [AVCaptureDevice] = []
    @State private var modelSize: Int64?
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
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)

            Divider()

            Form {
                switch selectedSection {
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
        .settingsScrollTarget(.dictation)
        .onAppear {
            microphoneAccess = Permissions.microphoneAccess()
            if settings.dictationEnabled { microphones = DictationCapture.microphones }
            Task {
                await coordinator.s1Downloader.checkStatus()
            }
        }
        .onChange(of: settings.dictationEnabled) { _, enabled in
            if enabled { microphones = DictationCapture.microphones }
        }
        .task {
            await coordinator.s1Downloader.checkStatus()
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification)
            {
                microphoneAccess = Permissions.microphoneAccess()
                if settings.dictationEnabled { microphones = DictationCapture.microphones }
                await coordinator.s1Downloader.checkStatus()
            }
        }
        .task(id: settings.dictationEnabled ? settings.dictationModel : nil) {
            modelSize = nil
            guard settings.dictationEnabled else { return }
            coordinator.models.refreshInstalledModels()
            await refreshModelSize(settings.dictationModel)
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

                Picker(selection: $bSettings.dictationIdleRelease) {
                    ForEach(DictationIdleRelease.allCases) { option in
                        Text(option.title(locale: .current)).tag(option)
                    }
                } label: {
                    SettingsRowTitle(.dictationMemory, "Unload model after")
                    Text("Frees memory when you are not dictating. Next dictation reloads.")
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
                Text("Audio & Memory")
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
            } header: {
                Text("Dictation Shortcuts")
            }

            Section {
                Picker(selection: familyBinding) {
                    ForEach(DictationModel.Family.allCases) { family in
                        Text(family.rawValue).tag(family)
                    }
                } label: {
                    SettingsRowTitle(.dictationModel, "Engine")
                    Text(settings.dictationModel.family.summary + " · " + settings.dictationModel.coverage)
                }
                Picker(selection: $bSettings.dictationModel) {
                    ForEach(
                        DictationModel.allCases.filter { $0.family == settings.dictationModel.family }
                    ) { model in
                        Text(model.variantTitle).tag(model)
                    }
                } label: {
                    SettingsRowTitle(.dictationModel, "Model")
                    Text(settings.dictationModel.summary)
                }

                let installed = coordinator.models.isInstalled(settings.dictationModel)
                let downloading = coordinator.models.downloading == settings.dictationModel
                if downloading {
                    DownloadProgressView(models: coordinator.models)
                } else {
                    LabeledContent {
                        if installed {
                            HStack(spacing: Theme.Spacing.md) {
                                Text("Installed · FluidAudio / Local")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Remove") { removeModel(settings.dictationModel) }
                                    .disabled(
                                        coordinator.models.transcribing || coordinator.models.removing != nil)
                            }
                        } else {
                            Button("Download") { downloadModel(settings.dictationModel) }
                                .disabled(coordinator.models.downloading != nil || coordinator.models.removing == settings.dictationModel)
                        }
                    } label: {
                        Text(installed ? "Installed" : "Not installed")
                        Text(modelDescription)
                    }
                }
            } header: {
                SettingsSectionHeader(.dictationModel)
            }
        }
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

            Toggle(isOn: $bSettings.dictationLiveInsertion) {
                SettingsRowTitle(.dictationOutput, "Insert while recording")
                Text("Paste each chunk as you speak, instead of only when finished.")
            }
        } header: {
            Text("Formatting & Rules")
        }

        Section {
            Toggle(isOn: $bSettings.dictationS1Enabled) {
                SettingsRowTitle(.dictationOutput, "Enable AI Polish (S1-mini)")
                Text("Clean up and format transcriptions with on-device S1-mini AI normalization.")
            }

            if settings.dictationS1Enabled {
                s1ModelStatusRow

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

                Picker(selection: $bSettings.dictationS1IdleRelease) {
                    ForEach(DictationIdleRelease.allCases) { option in
                        Text(option.title(locale: .current)).tag(option)
                    }
                } label: {
                    SettingsRowTitle(.dictationMemory, "Unload model after")
                    Text("Frees memory when S1-mini is not normalizing. Next polish reloads.")
                }
            }
        } header: {
            Text("AI Polish (S1-mini)")
        } footer: {
            Text("AI polish normalizes text using local standalone S1-mini (default) or Ollama with the S1 control line.")
        }
    }

    @ViewBuilder
    private var s1ModelStatusRow: some View {
        switch coordinator.s1Downloader.status {
        case .idle, .checking:
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking Ollama S1-mini status...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 2)

        case .installedDirect(let path):
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("S1-mini Direct Model Active (Default)")
                        .font(.system(size: 12, weight: .medium))
                    Text(path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Refresh") {
                    Task { await coordinator.s1Downloader.checkStatus() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 2)

        case .installedOllama(let modelName):
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("S1-mini Installed in Ollama")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(modelName) (484 MB)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    Task { await coordinator.s1Downloader.checkStatus() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 2)

        case .ollamaNotRunning:
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ollama is not running")
                        .font(.system(size: 12, weight: .medium))
                    Text("Start Ollama at localhost:11434 to run S1-mini offline.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Retry") {
                    Task { await coordinator.s1Downloader.checkStatus() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 2)

        case .notInstalled:
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("S1-mini Model Not Downloaded")
                        .font(.system(size: 12, weight: .medium))
                    Text("Download standalone s1-mini-1.0.gguf (484 MB) for fast, offline speech normalization.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    coordinator.s1Downloader.downloadDirectGGUF()
                } label: {
                    Label("Download (484 MB)", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.vertical, 2)

        case .downloading(let progress, let statusText):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text("Downloading S1-mini: \(statusText)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if progress > 0 {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Button("Cancel") {
                        coordinator.s1Downloader.cancelDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                ProgressView(value: progress > 0 ? progress : nil)
                    .progressViewStyle(.linear)
            }
            .padding(.vertical, 2)

        case .error(let message):
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download Failed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Retry") {
                    coordinator.s1Downloader.downloadDirectGGUF()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 2)
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
                    Label("Export your words", systemImage: "square.and.arrow.up")
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
        }

        let filteredItems = historySearchQuery.isEmpty
            ? coordinator.historyStore.items
            : coordinator.historyStore.items.filter { $0.text.localizedCaseInsensitiveContains(historySearchQuery) }

        if !filteredItems.isEmpty {
            Section {
                ForEach(filteredItems) { item in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack {
                            Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("· \(item.wordCount) words")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
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
                    panel.allowedContentTypes = [.json, .plainText]
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

    private var familyBinding: Binding<DictationModel.Family> {
        Binding(
            get: { settings.dictationModel.family },
            set: {
                settings.dictationModel = $0 == .parakeet ? .ultra : .qwenSmall
            })
    }

    private var modelDescription: String {
        let bytes = modelSize
        let size = bytes.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
        return size.map { "\($0)" } ?? "\(settings.dictationModel.approximateInstalledMegabytes) MB"
    }

    private func downloadModel(_ model: DictationModel) {
        Task { await coordinator.downloadModel(model) }
    }

    private func removeModel(_ model: DictationModel) {
        Task {
            await coordinator.removeModel(model)
            coordinator.models.refreshInstalledModels()
            await refreshModelSize(model)
        }
    }

    private func refreshModelSize(_ model: DictationModel) async {
        modelSize = await coordinator.models.installedSize(model)
    }

    private struct DownloadProgressView: View {
        let models: DictationModelStore

        var body: some View {
            let progress = models.downloadProgress
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                LabeledContent {
                    Button("Cancel") { models.cancelDownload() }
                } label: {
                    Text(title)
                }
                if let progress, progress.total > 0 {
                    ProgressView(value: Double(progress.received), total: Double(progress.total))
                        .tint(.accentColor)
                        .accessibilityLabel("Model download progress")
                    HStack {
                        let received = progress.received.formatted(.byteCount(style: .file))
                        let total = progress.total.formatted(.byteCount(style: .file))
                        Text("\(received) of \(total)")
                        Spacer()
                        Text(
                            Double(progress.received) / Double(progress.total),
                            format: .percent.precision(.fractionLength(0)))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Preparing model download")
                }
            }
        }

        private var title: LocalizedStringResource {
            switch models.downloading {
            case .qwenSmall, .qwenLarge:
                LocalizedStringResource(
                    "downloading-dictation-model-qwen",
                    defaultValue: "Downloading Qwen3-Audio…")
            case .redux:
                LocalizedStringResource(
                    "downloading-dictation-model-parakeet",
                    defaultValue: "Downloading Parakeet TDT…")
            case .ultra:
                LocalizedStringResource(
                    "downloading-dictation-model-parakeet-ultra",
                    defaultValue: "Downloading Parakeet Ultra…")
            case nil:
                LocalizedStringResource(
                    "downloading-dictation-model-general",
                    defaultValue: "Downloading…")
            }
        }
    }
}
