import AVFoundation
import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

@MainActor
@Observable
final class MeetingNotetakerCoordinator {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "MeetingNotetaker")

    enum Phase: Equatable {
        case idle
        case recording(startedAt: Date)
        case processing(progress: String)
        case completed(MeetingNote)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var notes: [MeetingNote] = []
    private(set) var isMuted = false
    private(set) var activeTitle: String = "Meeting"

    private let capture = DictationCapture()
    private let systemAudioCapture = SystemAudioTapCapture()
    private let models: DictationModelStore
    private let s1Polisher = DictationS1Polisher()
    private let groqAudio = GroqAudioService()
    private let deepgramAudio = DeepgramAudioService()
    private let groqPolish = GroqPolishService()
    private let settings: AppSettings
    private let store: TranscriptStore
    private let dictionaryStore: DictationDictionaryStore
    private let showMessage: (String, DialogTone) -> Void

    init(
        settings: AppSettings,
        models: DictationModelStore,
        store: TranscriptStore? = nil,
        dictionaryStore: DictationDictionaryStore? = nil,
        showMessage: @escaping (String, DialogTone) -> Void
    ) {
        self.settings = settings
        self.models = models
        self.store = store ?? TranscriptStore()
        self.dictionaryStore = dictionaryStore ?? DictationDictionaryStore()
        self.showMessage = showMessage
        self.capture.onAutoStopSilence = { [weak self] in self?.stopRecording() }
        loadNotes()
    }

    public var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    public func toggleMute() {
        isMuted.toggle()
        capture.setMuted(isMuted)
    }

    public func startRecording(title: String? = nil, startMuted: Bool? = nil) {
        guard !isRecording else { return }
        let mutedStart = startMuted ?? settings.dictationMeetingStartMuted
        activeTitle = title?.isEmpty == false ? title! : "Meeting"
        isMuted = mutedStart
        Task {
            do {
                if settings.dictationMeetingCapturesSystemAudio {
                    do {
                        try await systemAudioCapture.start()
                    } catch {
                        Self.logger.warning("System audio tap unavailable: \(error.localizedDescription)")
                    }
                }
                try await capture.start(
                    microphoneID: settings.dictationMicrophone,
                    whisperMode: false,
                    allowLongCapture: true,
                    startMuted: mutedStart,
                    autoStopSilenceSeconds: settings.dictationAutoStopSilenceSeconds
                )
                phase = .recording(startedAt: Date())
                showMessage(
                    mutedStart
                        ? String(localized: "Meeting recording started (muted)")
                        : String(localized: "Meeting recording started"),
                    .neutral
                )
            } catch {
                _ = systemAudioCapture.stop()
                phase = .failed(error.localizedDescription)
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    public func stopRecording() {
        guard case .recording(let startedAt) = phase else { return }
        let duration = Date().timeIntervalSince(startedAt)
        phase = .processing(progress: String(localized: "Processing meeting audio…"))

        Task {
            let micSamples = await capture.stop()
            let systemSamples = systemAudioCapture.stop()
            isMuted = false

            guard !micSamples.isEmpty || !systemSamples.isEmpty else {
                phase = .failed(String(localized: "No audio captured during meeting"))
                showMessage(String(localized: "No audio captured"), .danger)
                return
            }

            await processDualTrackMeeting(
                micSamples: micSamples,
                systemSamples: systemSamples,
                duration: max(duration, Double(max(micSamples.count, systemSamples.count)) / 16_000.0),
                titlePrefix: activeTitle
            )
        }
    }

    public func cancelRecording() {
        guard isRecording else { return }
        Task {
            _ = await capture.stop()
            _ = systemAudioCapture.stop()
            isMuted = false
            phase = .idle
            showMessage(String(localized: "Meeting recording cancelled"), .neutral)
        }
    }

    public func processAudioFile(url: URL) {
        phase = .processing(progress: String(localized: "Decoding audio file…"))
        Task {
            do {
                let samples = try await DictationFileTranscriber.extractSamples(from: url)
                let duration = Double(samples.count) / 16_000.0
                await processMeetingAudio(
                    samples: samples,
                    duration: duration,
                    titlePrefix: url.deletingPathExtension().lastPathComponent,
                    sourceURL: url.path
                )
            } catch {
                phase = .failed(error.localizedDescription)
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    private func processDualTrackMeeting(
        micSamples: [Float],
        systemSamples: [Float],
        duration: TimeInterval,
        titlePrefix: String
    ) async {
        phase = .processing(progress: String(localized: "Transcribing meeting audio…"))

        let hasMicSignal = micSamples.contains { abs($0) > 0.002 }
        let hasSystemSignal = systemSamples.contains { abs($0) > 0.002 }

        if !hasSystemSignal {
            await processMeetingAudio(samples: micSamples, duration: duration, titlePrefix: titlePrefix)
            return
        }

        do {
            var micTimed = TimedTranscript(text: "")
            var systemTimed = TimedTranscript(text: "")

            if hasMicSignal {
                micTimed = try await transcribeSamples(micSamples, diarizeSpeakers: nil)
                micTimed.segments = normalizeSegments(micTimed.segments).map { seg in
                    var next = seg
                    next.speaker = "Me"
                    return next
                }
            }
            systemTimed = try await transcribeSamples(
                systemSamples, diarizeSpeakers: settings.dictationSpeakerCount
            )
            systemTimed.segments = normalizeSegments(systemTimed.segments).map { seg in
                var next = seg
                if next.speaker.isEmpty || next.speaker == "Unattributed" {
                    next.speaker = "Others"
                } else {
                    next.speaker = next.speaker.replacingOccurrences(of: "Speaker", with: "Others")
                }
                return next
            }

            let mergedSegments = TranscriptSegmentBuilder.mergeTracks(
                mic: micTimed.segments, system: systemTimed.segments)
            let mixed = mixTracks(micSamples, systemSamples)
            let transcriptText = mergedSegments.map {
                "\($0.speaker): \($0.text)"
            }.joined(separator: "\n")

            await generateMemoAndNote(
                from: transcriptText,
                segments: mergedSegments,
                samples: mixed,
                duration: duration,
                titlePrefix: titlePrefix,
                sourceURL: nil
            )
        } catch {
            phase = .failed(error.localizedDescription)
            showMessage(error.localizedDescription, .danger)
        }
    }

    private func processMeetingAudio(
        samples: [Float],
        duration: TimeInterval,
        titlePrefix: String,
        sourceURL: String? = nil
    ) async {
        phase = .processing(progress: String(localized: "Transcribing meeting speech…"))
        do {
            let timed = try await transcribeSamples(samples, diarizeSpeakers: settings.dictationSpeakerCount)
            guard !timed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                phase = .failed(String(localized: "No speech detected in recording"))
                showMessage(String(localized: "No speech detected"), .neutral)
                return
            }
            let normalizedText = normalizeTranscript(timed.text)
            let normalizedSegments = normalizeSegments(timed.segments)
            await generateMemoAndNote(
                from: normalizedText,
                segments: normalizedSegments,
                samples: samples,
                duration: duration,
                titlePrefix: titlePrefix,
                sourceURL: sourceURL
            )
        } catch {
            phase = .failed(error.localizedDescription)
            showMessage(error.localizedDescription, .danger)
        }
    }

    private func normalizeTranscript(_ text: String) -> String {
        var cleaned = DictationTextFormatter.collapseRepetitions(text)
        cleaned = dictionaryStore.applyDictionaryAndPacks(cleaned)
        cleaned = dictionaryStore.applySnippets(cleaned)
        return cleaned
    }

    private func normalizeSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.map { seg in
            var next = seg
            next.text = normalizeTranscript(seg.text)
            return next
        }
    }

    private func transcribeSamples(_ samples: [Float], diarizeSpeakers: Int?) async throws -> TimedTranscript {
        if settings.dictationTranscriptionProvider == .cloud,
           DictationCloudSpeechService.hasAPIKey(
               for: settings.dictationCloudSpeechProvider,
               groqAPIKey: settings.groqAPIKey,
               deepgramAPIKey: settings.deepgramAPIKey
           ) {
            let result = try await DictationCloudSpeechService.transcribe(
                provider: settings.dictationCloudSpeechProvider,
                samples: samples,
                groqAudio: groqAudio,
                deepgramAudio: deepgramAudio,
                groqAPIKey: settings.groqAPIKey,
                deepgramAPIKey: settings.deepgramAPIKey,
                groqModel: settings.dictationGroqTranscriptionModel,
                deepgramModel: settings.dictationDeepgramModel,
                language: settings.dictationLanguage,
                keyterms: dictionaryStore.promptVocabularyHint()
            )
            return TimedTranscript(text: result.text)
        }
        let model = models.isInstalled(settings.dictationModel) ? settings.dictationModel : .redux
        var timed = try await models.transcribeTimed(
            samples,
            model: model,
            language: settings.dictationLanguage,
            useVAD: settings.dictationVADEnabled,
            diarizeSpeakers: diarizeSpeakers
        )
        let hindiMode = settings.dictationHindiMode
        let bengaliMode = settings.dictationBengaliMode
        let normalizeIndic: (String) -> String = { raw in
            let withBanglish = AvroPhoneticConverter.normalizeIfNeeded(
                raw,
                bengaliMode: bengaliMode,
                isCloud: false,
                localModel: model
            )
            return HinglishPhoneticConverter.normalizeIfNeeded(
                withBanglish,
                hindiMode: hindiMode,
                isCloud: false,
                localModel: model
            )
        }
        let normalized = normalizeIndic(timed.text)
        if normalized != timed.text {
            let normalizeWord: (TranscriptWord) -> TranscriptWord = { word in
                TranscriptWord(
                    text: normalizeIndic(word.text),
                    start: word.start,
                    end: word.end,
                    confidence: word.confidence
                )
            }
            let convertedSegments = timed.segments.map { seg in
                TranscriptSegment(
                    id: seg.id,
                    speaker: seg.speaker,
                    text: normalizeIndic(seg.text),
                    start: seg.start,
                    end: seg.end,
                    words: seg.words.map(normalizeWord)
                )
            }
            timed = TimedTranscript(
                text: normalized,
                words: timed.words.map(normalizeWord),
                segments: convertedSegments
            )
        }
        return timed
    }

    private func generateMemoAndNote(
        from transcript: String,
        segments: [TranscriptSegment],
        samples: [Float],
        duration: TimeInterval,
        titlePrefix: String,
        sourceURL: String?
    ) async {
        phase = .processing(progress: String(localized: "Extracting summary, action items & decisions…"))
        let recordID = UUID()
        var wavName: String?
        if !samples.isEmpty {
            let filename = "\(recordID.uuidString).wav"
            let url = store.audioDirectory.appending(path: filename)
            DictationHistoryStore.writeWAV(samples: samples, to: url)
            if FileManager.default.fileExists(atPath: url.path) { wavName = filename }
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let fallbackTitle = "\(titlePrefix) — \(formatter.string(from: Date()))"

        let draftRecord = TranscriptRecord(
            id: recordID,
            kind: .meeting,
            title: fallbackTitle,
            createdAt: Date(),
            duration: duration,
            text: transcript,
            rawText: transcript,
            segments: segments,
            sourceURL: sourceURL,
            audioFilename: wavName,
            modelID: settings.dictationModel.rawValue
        )

        let polishProvider: DictationPolishProvider =
            (settings.dictationPolishProvider == .groq && !settings.groqAPIKey.isEmpty) ? .groq : .localS1
        let extracted = await TranscriptAIService.generateStructuredNotes(
            from: draftRecord,
            provider: polishProvider,
            groqAPIKey: settings.groqAPIKey,
            groqModel: settings.dictationGroqPolishModel,
            polisher: s1Polisher,
            groq: groqPolish
        )

        var finalRecord = draftRecord
        if let extracted {
            if !extracted.title.isEmpty { finalRecord.title = extracted.title }
            finalRecord.summary = extracted.summary
            finalRecord.actionItems = extracted.actionItems
            finalRecord.decisions = extracted.decisions
        } else {
            finalRecord.summary = String(transcript.prefix(240))
        }

        store.upsert(finalRecord)
        loadNotes()
        let note = finalRecord.toMeetingNote()
        phase = .completed(note)
        Paster.copyPlainText(note.markdownMemo)
        showMessage(String(localized: "Meeting note & action items copied to clipboard"), .success)
    }

    public func importTranscript(from url: URL) async {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let name = url.deletingPathExtension().lastPathComponent
            let wordCount = content.split(separator: " ").count
            let estimatedDuration = Double(max(60, wordCount / 2))
            await generateMemoAndNote(
                from: content,
                segments: [],
                samples: [],
                duration: estimatedDuration,
                titlePrefix: "Imported: \(name)",
                sourceURL: url.path
            )
        } catch {
            phase = .failed(error.localizedDescription)
            showMessage(String(localized: "Could not read transcript file: \(error.localizedDescription)"), .danger)
        }
    }

    public func promptImportTranscript() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Meeting Transcript (Otter, Granola, Text, Markdown)")
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.importTranscript(from: url)
            }
        }
    }

    public func addNote(_ note: MeetingNote) {
        store.upsert(TranscriptRecord(from: note))
        loadNotes()
    }

    public func removeNote(id: UUID) {
        store.delete(id: id)
        loadNotes()
    }

    private func mixTracks(_ a: [Float], _ b: [Float]) -> [Float] {
        let len = max(a.count, b.count)
        guard len > 0 else { return [] }
        var mixed = [Float](repeating: 0, count: len)
        for i in 0..<len {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            mixed[i] = max(-1.0, min(1.0, (av + bv) * 0.7))
        }
        return mixed
    }

    private func loadNotes() {
        notes = store.all(kind: .meeting, limit: 500).map { $0.toMeetingNote() }
    }
}
