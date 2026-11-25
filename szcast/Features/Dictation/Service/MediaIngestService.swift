import Foundation

@MainActor
@Observable
final class MediaIngestService {
    struct BatchJob: Identifiable, Equatable, Sendable {
        enum Status: Equatable, Sendable {
            case queued
            case preparing
            case transcribing
            case completed(UUID)
            case failed(String)
        }

        let id: UUID
        let title: String
        let kind: TranscriptRecordKind
        let sourceURL: URL
        var status: Status
    }

    private(set) var jobs: [BatchJob] = []
    private(set) var isProcessingBatch = false
    private(set) var activeStatusText = ""

    nonisolated static func searchPodcasts(query: String) async throws -> [PodcastEpisodeResult] {
        try await MediaFetchService.searchPodcasts(query: query)
    }

    func enqueueFiles(
        _ urls: [URL],
        models: DictationModelStore,
        store: TranscriptStore,
        settings: AppSettings,
        dictionaryStore: DictationDictionaryStore
    ) {
        let files = MediaFetchService.collectMediaFiles(from: urls)
        guard !files.isEmpty else { return }
        for file in files {
            jobs.append(BatchJob(
                id: UUID(),
                title: file.deletingPathExtension().lastPathComponent,
                kind: .fileImport,
                sourceURL: file,
                status: .queued
            ))
        }
        runQueueIfNeeded(
            models: models, store: store, settings: settings, dictionaryStore: dictionaryStore)
    }

    func enqueueURL(
        _ url: URL,
        title: String? = nil,
        kind: TranscriptRecordKind = .urlImport,
        models: DictationModelStore,
        store: TranscriptStore,
        settings: AppSettings,
        dictionaryStore: DictationDictionaryStore
    ) {
        jobs.append(BatchJob(
            id: UUID(),
            title: title ?? (url.host ?? url.lastPathComponent),
            kind: kind,
            sourceURL: url,
            status: .queued
        ))
        runQueueIfNeeded(
            models: models, store: store, settings: settings, dictionaryStore: dictionaryStore)
    }

    func clearFinishedJobs() {
        jobs.removeAll { job in
            switch job.status {
            case .completed, .failed: true
            case .queued, .preparing, .transcribing: false
            }
        }
    }

    private func runQueueIfNeeded(
        models: DictationModelStore,
        store: TranscriptStore,
        settings: AppSettings,
        dictionaryStore: DictationDictionaryStore
    ) {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isProcessingBatch = false
                self.activeStatusText = ""
            }
            let s1Polisher = DictationS1Polisher()
            let groqPolish = GroqPolishService()
            let groqAudio = GroqAudioService()

            while let nextIndex = self.jobs.firstIndex(where: { $0.status == .queued }) {
                let job = self.jobs[nextIndex]
                self.jobs[nextIndex].status = .preparing
                self.activeStatusText = String(localized: "Fetching \(job.title)…")
                do {
                    let fetched: (samples: [Float], title: String, kind: TranscriptRecordKind, sourceURL: String)
                    if job.kind == .podcastImport && !job.sourceURL.pathExtension.isEmpty
                        && !(job.sourceURL.host ?? "").contains("podcasts.apple.com")
                    {
                        let samples = try await MediaFetchService.downloadAndDecodeDirectAudio(job.sourceURL)
                        fetched = (samples, job.title, .podcastImport, job.sourceURL.absoluteString)
                    } else {
                        fetched = try await MediaFetchService.fetchAudioSamples(from: job.sourceURL)
                    }

                    guard !fetched.samples.isEmpty else {
                        self.jobs[nextIndex].status = .failed(String(localized: "No audio track found"))
                        continue
                    }

                    self.jobs[nextIndex].status = .transcribing
                    self.activeStatusText = String(localized: "Transcribing \(fetched.title)…")

                    let timed: TimedTranscript
                    let usedModel: String
                    if settings.dictationTranscriptionProvider == .groq, !settings.groqAPIKey.isEmpty {
                        let text = try await groqAudio.transcribe(
                            samples: fetched.samples,
                            apiKey: settings.groqAPIKey,
                            model: settings.dictationGroqTranscriptionModel,
                            language: settings.dictationLanguage
                        )
                        timed = TimedTranscript(text: text)
                        usedModel = settings.dictationGroqTranscriptionModel
                    } else {
                        let model = models.isInstalled(settings.dictationModel) ? settings.dictationModel : .redux
                        guard models.isInstalled(model) else {
                            self.jobs[nextIndex].status = .failed(String(localized: "Download dictation model first"))
                            continue
                        }
                        usedModel = model.rawValue
                        timed = try await models.transcribeTimed(
                            fetched.samples,
                            model: model,
                            language: settings.dictationLanguage,
                            useVAD: settings.dictationVADEnabled,
                            diarizeSpeakers: settings.dictationSpeakerCount
                        )
                    }

                    var text = DictationTextFormatter.collapseRepetitions(timed.text)
                    text = dictionaryStore.applyDictionaryAndPacks(text)
                    text = dictionaryStore.applySnippets(text)

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
                        let provider: DictationPolishProvider =
                            (settings.dictationPolishProvider == .groq && !settings.groqAPIKey.isEmpty)
                            ? .groq : .localS1
                        text = await TranscriptAIService.polishLongTranscript(
                            text,
                            provider: provider,
                            s1Settings: s1,
                            groqAPIKey: settings.groqAPIKey,
                            groqModel: settings.dictationGroqPolishModel,
                            polisher: s1Polisher,
                            groq: groqPolish
                        )
                    }

                    let recID = UUID()
                    let wavName = "\(recID.uuidString).wav"
                    let wavURL = store.audioDirectory.appending(path: wavName)
                    DictationHistoryStore.writeWAV(samples: fetched.samples, to: wavURL)

                    let record = TranscriptRecord(
                        id: recID,
                        kind: job.kind == .podcastImport ? .podcastImport : fetched.kind,
                        title: fetched.title,
                        createdAt: Date(),
                        duration: Double(fetched.samples.count) / Double(DictationWire.sampleRate),
                        text: text,
                        rawText: timed.text,
                        segments: timed.segments,
                        sourceURL: fetched.sourceURL,
                        audioFilename: FileManager.default.fileExists(atPath: wavURL.path) ? wavName : nil,
                        modelID: usedModel
                    )
                    store.upsert(record)
                    self.jobs[nextIndex].status = .completed(recID)
                } catch {
                    self.jobs[nextIndex].status = .failed(error.localizedDescription)
                }
            }
        }
    }
}
