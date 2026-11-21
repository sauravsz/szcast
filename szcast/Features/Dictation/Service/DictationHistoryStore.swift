import Foundation
import OSLog

@MainActor
@Observable
final class DictationHistoryStore {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationHistory")
    private let fileURL: URL
    private let audioDirectory: URL

    private(set) var items: [DictationHistoryItem] = []

    init(
        fileURL: URL = AppPaths.applicationSupport().appending(path: "dictation-history.json"),
        audioDirectory: URL = AppPaths.applicationSupport().appending(path: "AudioRecordings", directoryHint: .isDirectory)
    ) {
        self.fileURL = fileURL
        self.audioDirectory = audioDirectory
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        load()
        pruneExpiredAudio()
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
        samples: [Float]? = nil
    ) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        var filename: String? = nil
        let id = UUID()
        if let samples, !samples.isEmpty {
            let fname = "\(id.uuidString).wav"
            let targetURL = audioDirectory.appending(path: fname)
            Self.writeWAV(samples: samples, to: targetURL)
            filename = fname
        }

        let item = DictationHistoryItem(
            id: id,
            text: clean,
            rawText: rawText,
            duration: duration,
            appName: appName,
            appBundleID: appBundleID,
            audioFilename: filename
        )
        items.insert(item, at: 0)
        // Keep latest 250 items
        if items.count > 250 {
            let removed = items.suffix(from: 250)
            for r in removed {
                if let fname = r.audioFilename {
                    try? FileManager.default.removeItem(at: audioDirectory.appending(path: fname))
                }
            }
            items = Array(items.prefix(250))
        }
        save()
    }

    func delete(id: UUID) {
        if let item = items.first(where: { $0.id == id }), let fname = item.audioFilename {
            try? FileManager.default.removeItem(at: audioDirectory.appending(path: fname))
        }
        items.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        items.removeAll()
        try? FileManager.default.removeItem(at: audioDirectory)
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        save()
    }

    private func pruneExpiredAudio() {
        let cutoff = Date().addingTimeInterval(-14 * 86400) // 14-day rolling retention matching Wispr Flow
        var updated = false
        for i in items.indices {
            if items[i].timestamp < cutoff, let fname = items[i].audioFilename {
                try? FileManager.default.removeItem(at: audioDirectory.appending(path: fname))
                items[i].audioFilename = nil
                updated = true
            }
        }
        if updated { save() }
    }

    static func writeWAV(samples: [Float], to url: URL) {
        let sampleRate: Int32 = 16000
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate: Int32 = sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)
        let blockAlign: Int16 = numChannels * (bitsPerSample / 8)
        let dataSize: Int32 = Int32(samples.count * 2)
        let chunkSize: Int32 = 36 + dataSize

        var data = Data()
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
            let pcm = Int16(clamped * 32767.0)
            withUnsafeBytes(of: pcm.littleEndian) { data.append(contentsOf: $0) }
        }

        try? data.write(to: url, options: .atomic)
    }

    private func load() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                items = try JSONDecoder().decode([DictationHistoryItem].self, from: data)
                return
            } catch {
                Self.logger.error("Failed to load dictation history: \(error.localizedDescription)")
            }
        }
    }

    private func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save dictation history: \(error.localizedDescription)")
        }
    }
}
