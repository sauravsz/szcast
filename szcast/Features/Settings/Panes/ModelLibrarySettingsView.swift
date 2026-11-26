import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ModelLibraryCategory: String, CaseIterable, Identifiable {
    case dictation = "Dictation Models"
    case text = "Text Models"

    var id: Self { self }
}

struct ModelLibrarySettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(SettingsNavigationState.self) private var navigation
    @Environment(AISettingsStore.self) private var aiSettings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI
    @Environment(QuickActionSettingsStore.self) private var quickActionSettings
    @Environment(DictationCoordinator.self) private var coordinator

    @State private var selectedCategory: ModelLibraryCategory = .dictation
    @State private var selectedFamilyFilter: DictationModel.Family?
    @State private var modelSizes: [DictationModel: Int64] = [:]
    @State private var textModelSizes: [DictationTextModel: Int64] = [:]
    @State private var supportSizes: [DictationSupportModel: Int64] = [:]
    @State private var providersPresented = false
    @State private var downloadErrorMessage: String?

    private var filteredSpeechModels: [DictationModel] {
        guard let selectedFamilyFilter else { return DictationModel.allCases }
        return DictationModel.allCases.filter { $0.family == selectedFamilyFilter }
    }

    var body: some View {
        @Bindable var bSettings = settings

        VStack(spacing: 0) {
            Picker("", selection: $selectedCategory) {
                ForEach(ModelLibraryCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, Theme.Spacing.md)

            Divider()

            Form {
                if let downloadErrorMessage {
                    Section {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(downloadErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Dismiss") { self.downloadErrorMessage = nil }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }

                if selectedCategory == .dictation {
                    speechRecognitionSection(bSettings: $bSettings)
                    audioToolsSection
                } else {
                    voicePolishSection(bSettings: $bSettings)
                    aiAndQuickActionsSection
                }
            }
            .formStyle(.grouped)
        }
        .settingsEditorPanel(isPresented: $providersPresented) {
            AIProvidersPanel(onDone: { providersPresented = false })
        }
        .task {
            syncCategoryForScrollRequest(navigation.scrollRequest)
            core.applyInstalledAILifecycle()
            await refreshLibraryStatus()
        }
        .onChange(of: navigation.scrollRequest) { _, request in
            syncCategoryForScrollRequest(request)
        }
        .onChange(of: settings.aiEnabled) {
            core.applyInstalledAILifecycle()
            syncAISelection()
        }
        .onChange(of: aiSettings.enabledInstalledProviders) {
            core.applyInstalledAILifecycle()
            syncAISelection()
        }
        .onChange(of: subscription.models) { syncAISelection() }
        .onChange(of: subscription.phase) { syncAISelection() }
        .onChange(of: installedAI.statuses) { syncAISelection() }
    }

    // MARK: - Dictation Models: Speech Recognition (ASR)

    @ViewBuilder
    private func speechRecognitionSection(bSettings: Bindable<AppSettings>) -> some View {
        Section {
            Picker(selection: bSettings.dictationTranscriptionProvider) {
                ForEach(DictationTranscriptionProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            } label: {
                SettingsRowTitle(.modelLibrarySpeech, "Transcription engine")
                Text("Choose between on-device CoreML models or Groq Cloud Whisper.")
            }

            if settings.dictationTranscriptionProvider == .parakeet {
                Picker(selection: $selectedFamilyFilter) {
                    Text("All families").tag(DictationModel.Family?.none)
                    ForEach(DictationModel.Family.allCases) { family in
                        Text(family.rawValue).tag(Optional(family))
                    }
                } label: {
                    SettingsRowTitle(.modelLibrarySpeech, "Speech model")
                    Text("Download offline CoreML models first, then choose which model is active.")
                }

                ForEach(filteredSpeechModels) { model in
                    speechModelRow(model)
                }
            } else {
                Picker(selection: bSettings.dictationGroqTranscriptionModel) {
                    Text("whisper-large-v3-turbo (Free)").tag("whisper-large-v3-turbo")
                } label: {
                    SettingsRowTitle(.modelLibrarySpeech, "Groq STT model")
                    Text("Cloud speech recognition powered by Groq LPU hardware (~250ms).")
                }

                groqKeyRow(bSettings: bSettings)
            }
        } header: {
            SettingsSectionHeader(.modelLibrarySpeech)
        }
    }

    @ViewBuilder
    private func speechModelRow(_ model: DictationModel) -> some View {
        let isSelected = settings.dictationModel == model
        let isInstalled = coordinator.models.isInstalled(model)
        let isDownloading = coordinator.models.downloading == model
        let isRemoving = coordinator.models.removing == model
        let isHot = coordinator.models.loadedModel == model && coordinator.models.isWorkerRunning
        let isPrewarming = !isHot && coordinator.models.isPrewarming && isSelected
        let sizeText = formattedModelSize(for: model)

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(model.title)
                            .font(.system(size: settings.settingsRowTitleFontSize, weight: isSelected ? .semibold : .medium))
                        Text(sizeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        if isSelected {
                            Text("Active")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                        }
                        if isHot {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("Loaded").font(.caption2).foregroundStyle(.green)
                        } else if isPrewarming {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                            Text("Warming…").font(.caption2).foregroundStyle(.orange)
                        }
                    }

                    Text("\(model.coverage) — \(model.summary)")
                        .font(.system(size: settings.settingsRowSubtitleFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: Theme.Spacing.sm)

                if isDownloading {
                    Button("Cancel") { coordinator.models.cancelDownload() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if isInstalled {
                    if !isSelected {
                        Button("Set Active") { activateSpeechModel(model) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else if !isHot && !isPrewarming {
                        Button("Prewarm") { coordinator.models.prewarm(model) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button {
                        removeSpeechModel(model)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(coordinator.models.transcribing || isRemoving || coordinator.models.removing != nil)
                    .help("Remove \(model.title)")
                } else {
                    Button("Download") { downloadSpeechModel(model) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(coordinator.models.downloading != nil || isRemoving)
                }
            }

            if isDownloading, let progress = coordinator.models.downloadProgress {
                downloadProgressBar(received: progress.received, total: progress.total)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Dictation Models: Audio Intelligence (VAD & Diarization)

    private var audioToolsSection: some View {
        Section {
            ForEach(DictationSupportModel.allCases) { support in
                supportModelRow(support)
            }
        } header: {
            SettingsSectionHeader(.modelLibraryAudioTools)
        }
    }

    @ViewBuilder
    private func supportModelRow(_ support: DictationSupportModel) -> some View {
        let isInstalled = coordinator.models.isSupportInstalled(support)
        let isDownloading = coordinator.models.downloadingSupport == support
        let isRemoving = coordinator.models.removingSupport == support
        let sizeText = supportSizes[support].map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "~\(support.approximateInstalledMegabytes) MB"

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        if support == .sileroVAD {
                            SettingsRowTitle(.modelLibraryAudioTools, "Silero VAD v6")
                        } else {
                            SettingsRowTitle(.modelLibraryAudioTools, "Speaker Diarization")
                        }
                        Text(sizeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        if isInstalled {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("Installed").font(.caption2).foregroundStyle(.green)
                        }
                    }
                    Text(support.summary)
                        .font(.system(size: settings.settingsRowSubtitleFontSize))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Theme.Spacing.sm)

                if isDownloading {
                    Button("Cancel") { coordinator.models.cancelSupportDownload() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if isInstalled {
                    Button {
                        removeSupportModel(support)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(coordinator.models.transcribing || isRemoving || coordinator.models.removingSupport != nil)
                    .help("Remove \(support.title)")
                } else {
                    Button("Download") { downloadSupportModel(support) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(coordinator.models.downloadingSupport != nil || isRemoving)
                }
            }

            if isDownloading, let progress = coordinator.models.supportDownloadProgress {
                downloadProgressBar(received: progress.received, total: progress.total)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Text Models: Local GGUF & Cloud Polish

    @ViewBuilder
    private func voicePolishSection(bSettings: Bindable<AppSettings>) -> some View {
        Section {
            Picker(selection: bSettings.dictationPolishProvider) {
                ForEach(DictationPolishProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            } label: {
                SettingsRowTitle(.modelLibraryPolish, "Normalization engine")
                Text("Select an on-device lightweight GGUF text model or Groq cloud cleanup.")
            }

            if settings.dictationPolishProvider == .localS1 {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        SettingsRowTitle(.modelLibraryPolish, "Local text models")
                        Text("Download lightweight GGUF models for local llama-server polish, then choose which model is active.")
                            .font(.system(size: settings.settingsRowSubtitleFontSize))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(DictationTextModel.allCases) { textModel in
                    localTextModelRow(textModel)
                }
            } else {
                Picker(selection: bSettings.dictationGroqPolishModel) {
                    Text("openai/gpt-oss-120b (Free · Large)").tag("openai/gpt-oss-120b")
                    Text("openai/gpt-oss-20b (Free · Fast)").tag("openai/gpt-oss-20b")
                    Text("qwen/qwen3.8-27b (Free)").tag("qwen/qwen3.8-27b")
                } label: {
                    SettingsRowTitle(.modelLibraryPolish, "Groq polish model")
                    Text("Speech cleanup and normalization via Groq cloud.")
                }

                groqKeyRow(bSettings: bSettings)
            }
        } header: {
            SettingsSectionHeader(.modelLibraryPolish)
        }
    }

    @ViewBuilder
    private func localTextModelRow(_ model: DictationTextModel) -> some View {
        let isSelected = settings.dictationLocalTextModel == model
        let isInstalled = coordinator.s1Downloader.isInstalled(model)
        let isDownloadingThis = coordinator.s1Downloader.isDownloading && coordinator.s1Downloader.activeDownloadModel == model
        let sizeText = formattedTextModelSize(for: model)

        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(model.title)
                            .font(.system(size: settings.settingsRowTitleFontSize, weight: isSelected ? .semibold : .medium))
                        Text(model.quantizationBadge)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        Text(sizeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        if isSelected {
                            Text("Active")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                        }
                    }

                    Text(model.summary)
                        .font(.system(size: settings.settingsRowSubtitleFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: Theme.Spacing.sm)

                if isDownloadingThis {
                    Button("Cancel") { coordinator.s1Downloader.cancelDownload() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if isInstalled {
                    if !isSelected {
                        Button("Set Active") {
                            settings.dictationLocalTextModel = model
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    Button {
                        removeTextModel(model)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(coordinator.s1Downloader.isDownloading)
                    .help("Remove \(model.title)")
                } else {
                    Button("Download") {
                        downloadErrorMessage = nil
                        coordinator.s1Downloader.download(model)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(coordinator.s1Downloader.isDownloading)

                    Button("Import…") { importLocalGGUFFile(for: model) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(coordinator.s1Downloader.isDownloading)
                }
            }

            if isDownloadingThis, case .downloading(let progress, let statusText) = coordinator.s1Downloader.status {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress > 0 ? progress : nil)
                        .tint(.accentColor)
                    HStack {
                        Text(statusText)
                        Spacer()
                        if progress > 0 {
                            Text("\(Int(progress * 100))%").monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if coordinator.s1Downloader.activeDownloadModel == nil,
               case .error(let msg) = coordinator.s1Downloader.status,
               settings.dictationLocalTextModel == model
            {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Text Models: AI Chat & Quick Actions LLMs

    private var aiAndQuickActionsSection: some View {
        Section {
            SettingsRow(
                title: "Providers",
                subtitle: providerSummary,
                anchor: .modelLibraryAIModels
            ) {
                Button("Manage…") { providersPresented = true }
            }

            if let status = appleIntelligenceStatus, let reason = status.message {
                LabeledContent {
                    if status.isSupported {
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(AppleIntelligence.settingsURL)
                        }
                    }
                } label: {
                    Label(reason, systemImage: "apple.intelligence")
                        .foregroundStyle(.secondary)
                }
            }

            AIModelSelectionRows(
                selection: aiSettings.defaultModel,
                select: { $0.map(aiSettings.select) },
                modelLabel: {
                    SettingsRowTitle(.modelLibraryAIModels, "Default model")
                },
                effortLabel: {
                    SettingsRowTitle(.modelLibraryAIModels, "Reasoning effort")
                }
            )

            AIModelSelectionRows(
                selection: quickActionSettings.model,
                select: quickActionSettings.select,
                modelLabel: {
                    SettingsRowTitle(.modelLibraryAIModels, "Quick Actions model")
                    Text("Unless a specific Quick Action sets its own override.")
                },
                effortLabel: {
                    SettingsRowTitle(.modelLibraryAIModels, "Quick Actions reasoning effort")
                }
            )
        } header: {
            SettingsSectionHeader(.modelLibraryAIModels)
        } footer: {
            Text("Manage cloud providers, API keys, and default local or cloud LLMs for AI Chat and Quick Actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers & Actions

    @ViewBuilder
    private func groqKeyRow(bSettings: Bindable<AppSettings>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                SettingsRowTitle(.modelLibrarySpeech, "Groq API key")
                Spacer()
                SecureField("gsk_...", text: bSettings.groqAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button {
                    if let url = URL(string: "https://console.groq.com/keys") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Get Key", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
            let key = settings.groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.hasPrefix("gsk_") {
                Label("Stored securely in macOS Keychain.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if key.isEmpty {
                Label("Required for Groq cloud speech or cleanup.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func downloadProgressBar(received: Int64, total: Int64) -> some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: Double(received), total: Double(total))
                    .tint(.accentColor)
                HStack {
                    Text("\(received.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))")
                    Spacer()
                    Text(Double(received) / Double(total), format: .percent.precision(.fractionLength(0)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        } else {
            ProgressView()
                .progressViewStyle(.linear)
        }
    }

    private func formattedModelSize(for model: DictationModel) -> String {
        if let bytes = modelSizes[model] {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        return "~\(model.approximateInstalledMegabytes) MB"
    }

    private func formattedTextModelSize(for model: DictationTextModel) -> String {
        if let bytes = textModelSizes[model] {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        return "~\(model.approximateMegabytes) MB"
    }

    private var appleIntelligenceStatus: AppleIntelligenceStatus? {
        aiSettings.isAppleIntelligenceAvailable() ? nil : AppleIntelligenceProvider.status()
    }

    private var providerSummary: String {
        var providers: [String] = []
        if subscription.isConnected { providers.append("Codex") }
        for kind in InstalledAIKind.managedCLIKinds
        where installedAI.status(for: kind).isReady {
            providers.append(kind.title)
        }
        if !aiSettings.connections.isEmpty {
            let count = aiSettings.connections.count
            providers.append(String(localized: "\(count) API connections"))
        }
        return providers.isEmpty
            ? String(localized: "No external providers ready") : providers.joined(separator: ", ")
    }

    private func syncAISelection() {
        aiSettings.reconcile(subscription: subscription, installedAI: installedAI)
    }

    private func syncCategoryForScrollRequest(_ request: SettingsScrollRequest?) {
        guard let anchor = request?.target.anchor else { return }
        if anchor == .modelLibraryPolish || anchor == .modelLibraryAIModels {
            selectedCategory = .text
        } else if anchor == .modelLibrarySpeech || anchor == .modelLibraryAudioTools {
            selectedCategory = .dictation
        }
    }

    private func activateSpeechModel(_ model: DictationModel) {
        guard coordinator.models.isInstalled(model) else { return }
        settings.dictationModel = model
        coordinator.models.prewarm(model)
    }

    private func downloadSpeechModel(_ model: DictationModel) {
        downloadErrorMessage = nil
        Task {
            do {
                try await coordinator.models.download(model)
                coordinator.models.refreshInstalledModels()
                if let bytes = await coordinator.models.installedSize(model) {
                    modelSizes[model] = bytes
                }
            } catch is CancellationError {
                // User cancelled download.
            } catch {
                downloadErrorMessage = String(localized: "Failed to download \(model.title): \(error.localizedDescription)")
            }
        }
    }

    private func removeSpeechModel(_ model: DictationModel) {
        Task {
            await coordinator.removeModel(model)
            coordinator.models.refreshInstalledModels()
            modelSizes[model] = nil
        }
    }

    private func removeTextModel(_ model: DictationTextModel) {
        Task {
            try? await coordinator.s1Downloader.removeModel(model)
            textModelSizes[model] = nil
        }
    }

    private func downloadSupportModel(_ support: DictationSupportModel) {
        downloadErrorMessage = nil
        Task {
            do {
                _ = try await coordinator.models.downloadSupportModel(support)
                coordinator.models.refreshInstalledModels()
                if let bytes = await coordinator.models.installedSupportSize(support) {
                    supportSizes[support] = bytes
                }
            } catch is CancellationError {
                // User cancelled download.
            } catch {
                downloadErrorMessage = String(localized: "Failed to download \(support.title): \(error.localizedDescription)")
            }
        }
    }

    private func removeSupportModel(_ support: DictationSupportModel) {
        Task {
            try? await coordinator.models.deleteSupportModel(support)
            coordinator.models.refreshInstalledModels()
            supportSizes[support] = nil
        }
    }

    private func importLocalGGUFFile(for model: DictationTextModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select \(model.fileName)"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                try? await coordinator.s1Downloader.importModelFile(from: url, as: model)
                if let bytes = coordinator.s1Downloader.installedSize(model) {
                    textModelSizes[model] = bytes
                }
            }
        }
    }

    private func refreshLibraryStatus() async {
        coordinator.models.refreshInstalledModels()
        await coordinator.s1Downloader.checkStatus()
        for model in DictationModel.allCases where coordinator.models.isInstalled(model) {
            if let size = await coordinator.models.installedSize(model) {
                modelSizes[model] = size
            }
        }
        for textModel in DictationTextModel.allCases where coordinator.s1Downloader.isInstalled(textModel) {
            if let size = coordinator.s1Downloader.installedSize(textModel) {
                textModelSizes[textModel] = size
            }
        }
        for support in DictationSupportModel.allCases where coordinator.models.isSupportInstalled(support) {
            if let size = await coordinator.models.installedSupportSize(support) {
                supportSizes[support] = size
            }
        }
    }
}
