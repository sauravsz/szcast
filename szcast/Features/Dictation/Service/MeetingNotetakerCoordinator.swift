import AVFoundation
import AppKit
import Foundation
import OSLog

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

    private let capture = DictationCapture()
    private let models: DictationModelStore
    private let s1Polisher = DictationS1Polisher()
    private let groqAudio = GroqAudioService()
    private let groqPolish = GroqPolishService()
    private let settings: AppSettings
    private let showMessage: (String, DialogTone) -> Void
    private let fileURL: URL

    init(
        settings: AppSettings,
        models: DictationModelStore,
        showMessage: @escaping (String, DialogTone) -> Void
    ) {
        self.settings = settings
        self.models = models
        self.showMessage = showMessage

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("szcast", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("meeting-notes.json")
        loadNotes()
    }

    public var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    public func startRecording() {
        guard !isRecording else { return }
        Task {
            do {
                try await capture.start(microphoneID: settings.dictationMicrophone, whisperMode: false)
                phase = .recording(startedAt: Date())
                showMessage(String(localized: "Meeting recording started"), .neutral)
            } catch {
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
            let samples = await capture.stop()
            guard !samples.isEmpty else {
                phase = .failed(String(localized: "No audio captured during meeting"))
                showMessage(String(localized: "No audio captured"), .danger)
                return
            }

            await processMeetingAudio(samples: samples, duration: duration, titlePrefix: "Meeting")
        }
    }

    public func cancelRecording() {
        guard isRecording else { return }
        Task {
            _ = await capture.stop()
            phase = .idle
            showMessage(String(localized: "Meeting recording cancelled"), .neutral)
        }
    }

    public func processAudioFile(url: URL) {
        phase = .processing(progress: String(localized: "Decoding audio file…"))
        Task {
            do {
                let samples = try await DictationFileTranscriber.extractSamples(from: url)
                let duration = Double(samples.count) / 16000.0
                await processMeetingAudio(samples: samples, duration: duration, titlePrefix: url.deletingPathExtension().lastPathComponent)
            } catch {
                phase = .failed(error.localizedDescription)
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    private func processMeetingAudio(samples: [Float], duration: TimeInterval, titlePrefix: String) async {
        phase = .processing(progress: String(localized: "Transcribing meeting speech…"))

        let transcript: String
        do {
            if settings.dictationTranscriptionProvider == .groq, !settings.groqAPIKey.isEmpty {
                transcript = try await groqAudio.transcribe(
                    samples: samples,
                    apiKey: settings.groqAPIKey,
                    model: settings.dictationGroqTranscriptionModel,
                    language: settings.dictationLanguage
                )
            } else {
                let model = models.isInstalled(settings.dictationModel) ? settings.dictationModel : .redux
                transcript = try await models.transcribe(samples, model: model, language: settings.dictationLanguage)
            }
        } catch {
            phase = .failed(error.localizedDescription)
            showMessage(error.localizedDescription, .danger)
            return
        }

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .failed(String(localized: "No speech recognized in meeting audio"))
            showMessage(String(localized: "No speech recognized in meeting"), .neutral)
            return
        }

        await generateMemoAndNote(from: transcript, duration: duration, titlePrefix: titlePrefix)
    }

    private func generateMemoAndNote(from transcript: String, duration: TimeInterval, titlePrefix: String) async {
        phase = .processing(progress: String(localized: "Generating meeting summary & action items…"))

        let memoPrompt = """
        You are an executive meeting assistant. Analyze the provided meeting transcript and produce clean markdown notes with:
        1. Executive Summary: A clear 2-3 paragraph summary of the meeting discussion.
        2. Key Decisions: Bullet points of all decisions reached.
        3. Action Items: A bulleted checklist of tasks with owners if mentioned.
        Do not include pleasantries. Output only the structured markdown notes.
        """

        var summaryText = ""
        let s1 = DictationS1Settings(
            enabled: true,
            tone: .formal,
            structure: .lists,
            context: .general,
            idleRelease: settings.dictationS1IdleRelease
        )

        if settings.dictationPolishProvider == .groq, !settings.groqAPIKey.isEmpty {
            if let memo = try? await groqPolish.transform(
                text: transcript,
                instruction: memoPrompt,
                apiKey: settings.groqAPIKey,
                model: settings.dictationGroqPolishModel
            ) {
                summaryText = memo
            }
        }

        if summaryText.isEmpty {
            summaryText = await s1Polisher.transform(
                text: transcript,
                instruction: memoPrompt,
                settings: s1
            )
        }

        let title = "\(titlePrefix) (\(Date().formatted(date: .abbreviated, time: .shortened)))"
        let note = MeetingNote(
            title: title,
            date: Date(),
            duration: duration,
            transcript: transcript,
            summary: summaryText.isEmpty ? transcript : summaryText
        )

        addNote(note)
        phase = .completed(note)

        // Copy markdown memo to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.markdownMemo, forType: .string)
        showMessage(String(localized: "Meeting notes generated & copied to clipboard"), .success)
    }

    public func importTranscript(from url: URL) async {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            showMessage(String(localized: "Failed to read transcript file"), .danger)
            return
        }

        phase = .processing(progress: "Importing transcript…")
        let titleBase = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        await generateMemoAndNote(
            from: content,
            duration: 0,
            titlePrefix: titleBase
        )
    }

    public func promptImportTranscript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.text, .plainText, .json]
        panel.prompt = "Import"
        panel.message = "Choose an Otter.ai or Granola transcript to import into Meeting Notetaker"

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                await self?.importTranscript(from: url)
            }
        }
    }

    public func addNote(_ note: MeetingNote) {
        notes.insert(note, at: 0)
        saveNotes()
    }

    public func removeNote(id: UUID) {
        notes.removeAll { $0.id == id }
        saveNotes()
    }

    private func loadNotes() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([MeetingNote].self, from: data) {
            self.notes = decoded
        }
    }

    private func saveNotes() {
        if let encoded = try? JSONEncoder().encode(notes) {
            try? encoded.write(to: fileURL, options: .atomic)
        }
    }
}
