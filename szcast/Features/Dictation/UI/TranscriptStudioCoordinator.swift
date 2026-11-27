import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
@Observable
final class TranscriptStudioCoordinator {
    enum StudioTab: String, CaseIterable, Identifiable {
        case transcript = "Transcript"
        case notes = "Notes"
        case askAI = "Ask AI"
        var id: String { rawValue }
    }

    struct QAMessage: Identifiable, Equatable {
        let id = UUID()
        let isUser: Bool
        let text: String
    }

    private let store: TranscriptStore
    private let models: DictationModelStore
    private let settings: AppSettings
    private let dictionaryStore: DictationDictionaryStore
    private let meetingNotetaker: MeetingNotetakerCoordinator
    private let showMessage: (String, DialogTone) -> Void

    let ingest = MediaIngestService()
    let playback = TranscriptPlaybackCoordinator()
    let undoManager = UndoManager()

    var selectedRecordID: UUID?
    var searchQuery = ""
    var selectedKind: TranscriptRecordKind? = nil
    var activeTab: StudioTab = .transcript
    var isFindBarVisible = false
    var findQuery = ""
    var replaceQuery = ""
    var findCaseSensitive = false
    var isURLSheetPresented = false
    var isBusyProcessing = false
    var podcastQuery = ""
    var podcastResults: [PodcastEpisodeResult] = []
    var isSearchingPodcasts = false
    var qaHistories: [UUID: [QAMessage]] = [:]
    var isAnsweringQuestion = false

    @ObservationIgnored private let windowController: AppWindowController
    @ObservationIgnored private let polisher = DictationS1Polisher()
    @ObservationIgnored private let groqPolish = GroqPolishService()

    init(
        store: TranscriptStore,
        models: DictationModelStore,
        settings: AppSettings,
        dictionaryStore: DictationDictionaryStore,
        meetingNotetaker: MeetingNotetakerCoordinator,
        activationPolicy: ActivationPolicy,
        showMessage: @escaping (String, DialogTone) -> Void
    ) {
        self.store = store
        self.models = models
        self.settings = settings
        self.dictionaryStore = dictionaryStore
        self.meetingNotetaker = meetingNotetaker
        self.showMessage = showMessage
        self.windowController = AppWindowController(
            title: String(localized: "Transcript Studio"),
            contentSize: CGSize(width: 1020, height: 680),
            minimumSize: CGSize(width: 780, height: 500),
            resizable: true,
            autosaveName: "TranscriptStudioWindow",
            activation: activationPolicy,
            closesOnEscape: false
        )
    }

    var filteredRecords: [TranscriptRecord] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return selectedKind == nil ? store.records : store.records.filter { $0.kind == selectedKind }
        }
        return store.search(query: trimmed, kind: selectedKind, limit: 300)
    }

    var selectedRecord: TranscriptRecord? {
        guard let id = selectedRecordID ?? filteredRecords.first?.id else { return nil }
        return store.records.first(where: { $0.id == id }) ?? store.record(id: id)
    }

    var meetingState: MeetingNotetakerCoordinator { meetingNotetaker }
    var transcriptStore: TranscriptStore { store }
    var modelStore: DictationModelStore { models }
    var appSettings: AppSettings { settings }

    func showWindow(selecting id: UUID? = nil, openURLSheet: Bool = false) {
        store.reload()
        if let id { selectedRecordID = id }
        else if selectedRecordID == nil { selectedRecordID = store.records.first?.id }
        if openURLSheet { isURLSheetPresented = true }
        NSApp.activate(ignoringOtherApps: true)
        windowController.show {
            TranscriptStudioWindowView(coordinator: self)
        }
        playback.prepare(record: selectedRecord, store: store)
    }

    func selectRecord(_ id: UUID?) {
        selectedRecordID = id
        playback.prepare(record: selectedRecord, store: store)
    }

    func updateTitle(_ newTitle: String, for record: TranscriptRecord) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != record.title else { return }
        var updated = record
        updated.title = trimmed
        updated.updatedAt = Date()
        store.upsert(updated)
    }

    func renameSpeaker(oldName: String, to newName: String, in record: TranscriptRecord) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != oldName else { return }
        let before = record
        let after = record.renamingSpeaker(oldName, to: clean)
        applyUndoableEdit(previous: before, updated: after, actionName: "Rename Speaker")
    }

    func replaceAllOccurrences(in record: TranscriptRecord) {
        guard !findQuery.isEmpty else { return }
        let (updated, count) = record.replacingOccurrences(
            of: findQuery, with: replaceQuery, caseSensitive: findCaseSensitive)
        guard count > 0 else {
            showMessage(String(localized: "No matches found"), .neutral)
            return
        }
        applyUndoableEdit(previous: record, updated: updated, actionName: "Replace All")
        showMessage(String(localized: "Replaced \(count) occurrence(s)"), .success)
    }

    private func applyUndoableEdit(
        previous: TranscriptRecord, updated: TranscriptRecord, actionName: String
    ) {
        store.upsert(updated)
        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                target.applyUndoableEdit(previous: updated, updated: previous, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    func deleteRecord(_ record: TranscriptRecord) {
        if playback.loadedRecordID == record.id { playback.stop() }
        store.delete(id: record.id)
        if selectedRecordID == record.id {
            selectedRecordID = filteredRecords.first?.id
        }
        playback.prepare(record: selectedRecord, store: store)
    }

    func pickMediaFilesAndFolders() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Transcribe Audio, Video Files or Folders")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.ingest.enqueueFiles(
                    panel.urls,
                    models: self.models,
                    store: self.store,
                    settings: self.settings,
                    dictionaryStore: self.dictionaryStore
                )
            }
        }
    }

    func handleDroppedURLs(_ urls: [URL]) {
        ingest.enqueueFiles(
            urls,
            models: models,
            store: store,
            settings: settings,
            dictionaryStore: dictionaryStore
        )
    }

    func ingestURLString(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            showMessage(String(localized: "Enter a valid http/https URL"), .danger)
            return
        }
        isURLSheetPresented = false
        ingest.enqueueURL(
            url,
            kind: (url.host?.contains("podcasts.apple.com") == true) ? .podcastImport : .urlImport,
            models: models,
            store: store,
            settings: settings,
            dictionaryStore: dictionaryStore
        )
    }

    func transcribePodcastEpisode(_ episode: PodcastEpisodeResult) {
        guard let target = episode.episodeURL ?? episode.applePodcastsURL else { return }
        isURLSheetPresented = false
        ingest.enqueueURL(
            target,
            title: "\(episode.showName) — \(episode.episodeTitle)",
            kind: .podcastImport,
            models: models,
            store: store,
            settings: settings,
            dictionaryStore: dictionaryStore
        )
    }

    func runPodcastSearch() {
        let query = podcastQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearchingPodcasts = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSearchingPodcasts = false }
            do {
                self.podcastResults = try await MediaIngestService.searchPodcasts(query: query)
            } catch {
                self.showMessage(error.localizedDescription, .danger)
            }
        }
    }

    func rediarize(_ record: TranscriptRecord, speakerCount: Int) {
        guard let audioURL = store.audioURL(for: record) else {
            showMessage(String(localized: "Original audio file unavailable for re-diarization"), .danger)
            return
        }
        let model = models.isInstalled(settings.dictationModel) ? settings.dictationModel : .redux
        guard models.isInstalled(model) else {
            showMessage(String(localized: "Download a dictation model in Settings first"), .danger)
            return
        }
        isBusyProcessing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isBusyProcessing = false }
            do {
                _ = try? await self.models.downloadSupportModel(.speakerDiarization)
                let samples = try await DictationFileTranscriber.extractSamples(from: audioURL)
                let timed = try await self.models.transcribeTimed(
                    samples,
                    model: model,
                    language: self.settings.dictationLanguage,
                    useVAD: self.settings.dictationVADEnabled,
                    diarizeSpeakers: speakerCount
                )
                var updated = record
                updated.segments = timed.segments
                updated.text = timed.text.isEmpty ? record.text : timed.text
                updated.updatedAt = Date()
                self.store.upsert(updated)
                self.showMessage(String(localized: "Re-diarized speaker turns"), .success)
            } catch {
                self.showMessage(error.localizedDescription, .danger)
            }
        }
    }

    func generateNotes(for record: TranscriptRecord) {
        isBusyProcessing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isBusyProcessing = false }
            let provider = DictationPolishProvider.resolved(
                preferred: self.settings.dictationPolishProvider,
                groqAPIKey: self.settings.groqAPIKey
            )
            guard let notes = await TranscriptAIService.generateStructuredNotes(
                from: record,
                provider: provider,
                groqAPIKey: self.settings.groqAPIKey,
                groqModel: self.settings.dictationGroqPolishModel,
                polisher: self.polisher,
                groq: self.groqPolish
            ) else {
                self.showMessage(String(localized: "Could not generate notes — check S1-mini or Groq settings"), .danger)
                return
            }
            var updated = record
            updated.summary = notes.summary
            updated.actionItems = notes.actionItems
            updated.decisions = notes.decisions
            if record.title.hasPrefix("Meeting") || record.title.count < 8 {
                updated.title = notes.title
            }
            updated.updatedAt = Date()
            self.store.upsert(updated)
            self.activeTab = .notes
        }
    }

    func askQuestion(_ question: String, for record: TranscriptRecord) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        qaHistories[record.id, default: []].append(QAMessage(isUser: true, text: trimmed))
        isAnsweringQuestion = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isAnsweringQuestion = false }
            let provider = DictationPolishProvider.resolved(
                preferred: self.settings.dictationPolishProvider,
                groqAPIKey: self.settings.groqAPIKey
            )
            do {
                let answer = try await TranscriptAIService.askQuestion(
                    trimmed,
                    about: record,
                    provider: provider,
                    groqAPIKey: self.settings.groqAPIKey,
                    groqModel: self.settings.dictationGroqPolishModel,
                    polisher: self.polisher,
                    groq: self.groqPolish
                )
                self.qaHistories[record.id, default: []].append(QAMessage(isUser: false, text: answer))
            } catch {
                self.qaHistories[record.id, default: []].append(
                    QAMessage(isUser: false, text: "Error: \(error.localizedDescription)")
                )
            }
        }
    }

    func export(_ record: TranscriptRecord, format: TranscriptExportFormat) {
        let savePanel = NSSavePanel()
        savePanel.title = "Export \(format.displayName)"
        let baseName = record.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        savePanel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        if let utType = UTType(filenameExtension: format.fileExtension) {
            savePanel.allowedContentTypes = [utType]
        }
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                let data = try TranscriptExporter.exportData(record, format: format) {
                    TranscriptPDFExporter.render(record: $0)
                }
                try data.write(to: url, options: .atomic)
                self?.showMessage("Exported \(url.lastPathComponent)", .success)
            } catch {
                self?.showMessage(error.localizedDescription, .danger)
            }
        }
    }
}
