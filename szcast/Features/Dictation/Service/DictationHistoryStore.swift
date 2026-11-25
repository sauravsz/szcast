import Foundation
import OSLog

@MainActor
@Observable
final class DictationHistoryStore {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationHistory")

    let store: TranscriptStore
    private(set) var items: [DictationHistoryItem] = []
    private let fileURL: URL
    private let audioDirectory: URL
    private let retentionDays = 14

    init(
        fileURL: URL = AppPaths.applicationSupport().appending(path: "dictation-history.json"),
        audioDirectory: URL = AppPaths.applicationSupport().appending(
            path: "AudioRecordings", directoryHint: .isDirectory)
    ) {
        self.fileURL = fileURL
        self.audioDirectory = audioDirectory
        let dbURL = fileURL.deletingLastPathComponent().appendingPathComponent("transcripts.sqlite3")
        self.store = TranscriptStore(databaseURL: dbURL, audioDirectory: audioDirectory)
        let notesURL = fileURL.deletingLastPathComponent().appendingPathComponent("meeting-notes.json")
        store.importLegacyJSONIfNeeded(historyFileURL: fileURL, notesFileURL: notesURL)
        store.purgeAudioOlderThan(days: retentionDays, kind: .dictation)
        refreshItems()
    }

    func refreshItems() {
        items = store.all(kind: .dictation, limit: 2_000).map { $0.toHistoryItem() }
    }

    func audioURL(for item: DictationHistoryItem) -> URL? {
        guard let filename = item.audioFilename else { return nil }
        let url = audioDirectory.appending(path: filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func add(
        text: String,
        rawText: String = "",
        duration: TimeInterval = 0,
        appName: String? = nil,
        appBundleID: String? = nil,
        samples: [Float]? = nil,
        words: [TranscriptWord] = [],
        segments: [TranscriptSegment] = [],
        modelID: String? = nil,
        kind: TranscriptRecordKind = .dictation
    ) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let id = UUID()
        var filename: String?
        if let samples, !samples.isEmpty {
            let wavName = "\(id.uuidString).wav"
            let wavURL = audioDirectory.appending(path: wavName)
            Self.writeWAV(samples: samples, to: wavURL)
            if FileManager.default.fileExists(atPath: wavURL.path) {
                filename = wavName
            }
        }

        let resolvedSegments: [TranscriptSegment]
        if !segments.isEmpty {
            resolvedSegments = segments
        } else if !words.isEmpty {
            resolvedSegments = TranscriptSegmentBuilder.build(words: words, fallbackText: clean)
        } else {
            resolvedSegments = [TranscriptSegment(speaker: "", text: clean, start: 0, end: max(0, duration))]
        }

        let record = TranscriptRecord(
            id: id,
            kind: kind,
            createdAt: Date(),
            duration: duration,
            text: clean,
            rawText: rawText.isEmpty ? clean : rawText,
            segments: resolvedSegments,
            audioFilename: filename,
            appName: appName,
            appBundleID: appBundleID,
            modelID: modelID
        )
        store.upsert(record)
        refreshItems()
    }

    func delete(id: UUID) {
        store.delete(id: id)
        refreshItems()
    }

    func clearAll() {
        store.clearAll(kind: .dictation)
        refreshItems()
    }

    static func writeWAV(samples: [Float], to url: URL) {
        let sampleRate: Int32 = 16_000
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate: Int32 = sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)
        let blockAlign: Int16 = numChannels * (bitsPerSample / 8)
        let dataSize: Int32 = Int32(samples.count * 2)
        let chunkSize: Int32 = 36 + dataSize

        var data = Data(capacity: 44 + samples.count * 2)
        data.append(contentsOf: "RIFF".utf8)
        withUnsafeBytes(of: chunkSize.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        let subchunk1Size: Int32 = 16
        withUnsafeBytes(of: subchunk1Size.littleEndian) { data.append(contentsOf: $0) }
        let audioFormat: Int16 = 1
        withUnsafeBytes(of: audioFormat.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: numChannels.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: sampleRate.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: "data".utf8)
        withUnsafeBytes(of: dataSize.littleEndian) { data.append(contentsOf: $0) }

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let pcm = Int16(clamped * 32_767.0)
            withUnsafeBytes(of: pcm.littleEndian) { data.append(contentsOf: $0) }
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Failed to write WAV: \(error.localizedDescription)")
        }
    }
}
