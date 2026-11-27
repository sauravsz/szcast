import AVFoundation
import Foundation
import OSLog

@MainActor
@Observable
final class DictationHistoryStore {
    nonisolated private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationHistory")

    let store: TranscriptStore
    private(set) var items: [DictationHistoryItem] = []
    private(set) var playingItemID: UUID?
    private(set) var hasMoreItems = false
    private(set) var activeSearchQuery = ""
    private let fileURL: URL
    private let audioDirectory: URL
    private(set) var retentionDays = 14
    var skipAudioArchiveOnSuccess = false
    private var loadedLimit = 60
    private let pageStep = 60
    @ObservationIgnored private var pendingWrites: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var playbackTimer: Task<Void, Never>?

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

    func refreshItems(limit: Int? = nil, query: String? = nil) {
        if let limit { loadedLimit = max(pageStep, limit) }
        if let query { activeSearchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines) }

        if !activeSearchQuery.isEmpty {
            let matches = store.search(query: activeSearchQuery, kind: .dictation, limit: 200)
            hasMoreItems = false
            items = matches.map { $0.toHistoryItem() }
            return
        }

        let probe = store.all(kind: .dictation, limit: loadedLimit + 1)
        hasMoreItems = probe.count > loadedLimit
        items = probe.prefix(loadedLimit).map { $0.toHistoryItem() }
    }

    func loadMore() {
        loadedLimit += pageStep
        refreshItems()
    }

    /// Configures archived audio retention (`0` = text-only for completed dictations while preserving recovery clips).
    func applyRetentionPolicy(days: Int) {
        let clamped = max(0, days)
        retentionDays = clamped
        skipAudioArchiveOnSuccess = (clamped == 0)
        if clamped == 0 {
            purgeCompletedAudioArchives()
        } else {
            store.purgeAudioOlderThan(days: clamped, kind: .dictation)
            refreshItems()
        }
    }

    private func purgeCompletedAudioArchives() {
        let records = store.all(kind: .dictation, limit: 5_000)
        var changed = false
        for var rec in records where rec.audioFilename != nil && !rec.text.hasPrefix("[Dictation Recovery") {
            if let file = rec.audioFilename {
                try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(file))
            }
            rec.audioFilename = nil
            store.upsert(rec, refreshCache: false)
            changed = true
        }
        if changed { refreshItems() }
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

    /// Inserts immediately in memory (`O(1)`) while compressing audio (`.m4a` AAC, WAV fallback) and writing SQLite off-main.
    func addAsync(
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
        let now = Date()
        let isRecovery = clean.hasPrefix("[Dictation Recovery")
        let effectiveSamples: [Float]? = (skipAudioArchiveOnSuccess && !isRecovery) ? nil : samples
        let hasAudio = effectiveSamples?.isEmpty == false
        let preferredName = hasAudio ? "\(id.uuidString).m4a" : nil
        let optimistic = DictationHistoryItem(
            id: id,
            timestamp: now,
            text: clean,
            rawText: rawText.isEmpty ? clean : rawText,
            duration: duration,
            appName: appName,
            appBundleID: appBundleID,
            audioFilename: preferredName
        )
        items.insert(optimistic, at: 0)
        if items.count > max(loadedLimit, 200) {
            items.removeLast(items.count - max(loadedLimit, 200))
            hasMoreItems = true
        }

        let resolvedSegments: [TranscriptSegment]
        if !segments.isEmpty {
            resolvedSegments = segments
        } else if !words.isEmpty {
            resolvedSegments = TranscriptSegmentBuilder.build(words: words, fallbackText: clean)
        } else {
            resolvedSegments = [TranscriptSegment(speaker: "", text: clean, start: 0, end: max(0, duration))]
        }

        let audioDir = self.audioDirectory
        let rawCopy = rawText.isEmpty ? clean : rawText
        let task = Task { [weak self] in
            let finalFilename: String? = await Task.detached(priority: .utility) {
                guard let effectiveSamples, !effectiveSamples.isEmpty else { return nil }
                let m4aName = "\(id.uuidString).m4a"
                let m4aURL = audioDir.appending(path: m4aName)
                if Self.writeCompressedM4A(samples: effectiveSamples, to: m4aURL) {
                    return m4aName
                }
                let wavName = "\(id.uuidString).wav"
                let wavURL = audioDir.appending(path: wavName)
                Self.writeWAV(samples: effectiveSamples, to: wavURL)
                return FileManager.default.fileExists(atPath: wavURL.path) ? wavName : nil
            }.value

            guard let self else { return }
            defer { self.pendingWrites.removeValue(forKey: id) }
            if let idx = self.items.firstIndex(where: { $0.id == id }) {
                self.items[idx].audioFilename = finalFilename
            }
            let record = TranscriptRecord(
                id: id,
                kind: kind,
                createdAt: now,
                duration: duration,
                text: clean,
                rawText: rawCopy,
                segments: resolvedSegments,
                audioFilename: finalFilename,
                appName: appName,
                appBundleID: appBundleID,
                modelID: modelID
            )
            self.store.upsert(record, refreshCache: false)
        }
        pendingWrites[id] = task
    }

    func flushPendingWrites() async {
        let tasks = Array(pendingWrites.values)
        for task in tasks {
            await task.value
        }
    }

    func delete(id: UUID) {
        pendingWrites[id]?.cancel()
        pendingWrites.removeValue(forKey: id)
        store.delete(id: id)
        refreshItems()
    }

    func clearAll() {
        stopAudioPlayback()
        for task in pendingWrites.values { task.cancel() }
        pendingWrites.removeAll()
        store.clearAll(kind: .dictation)
        refreshItems()
    }

    func updateTranscription(
        id: UUID,
        text: String,
        rawText: String,
        modelID: String?,
        words: [TranscriptWord] = [],
        segments: [TranscriptSegment] = []
    ) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].text = clean
            items[idx].rawText = rawText.isEmpty ? clean : rawText
        }
        guard var existing = store.record(id: id) else { return }
        let resolvedSegments: [TranscriptSegment]
        if !segments.isEmpty {
            resolvedSegments = segments
        } else if !words.isEmpty {
            resolvedSegments = TranscriptSegmentBuilder.build(words: words, fallbackText: clean)
        } else {
            resolvedSegments = [TranscriptSegment(speaker: "", text: clean, start: 0, end: max(0, existing.duration))]
        }
        existing.text = clean
        existing.rawText = rawText.isEmpty ? clean : rawText
        existing.title = TranscriptRecord.defaultTitle(for: clean, kind: existing.kind, date: existing.createdAt)
        existing.segments = resolvedSegments
        existing.modelID = modelID ?? existing.modelID
        existing.wordCount = clean.split { $0.isWhitespace || $0.isNewline }.count
        existing.updatedAt = Date()
        store.upsert(existing, refreshCache: false)
    }

    func toggleAudioPlayback(for item: DictationHistoryItem) {
        if playingItemID == item.id {
            stopAudioPlayback()
            return
        }
        stopAudioPlayback()
        guard let url = audioURL(for: item),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return }
        audioPlayer = player
        playingItemID = item.id
        player.play()
        playbackTimer = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.audioPlayer?.isPlaying == true {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard let self, !Task.isCancelled else { return }
            self.playingItemID = nil
            self.audioPlayer = nil
            self.playbackTimer = nil
        }
    }

    func stopAudioPlayback() {
        playbackTimer?.cancel()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        playingItemID = nil
    }

    /// Reads any archived `.m4a` or `.wav` recording into 16 kHz mono Float32 samples for re-transcription.
    nonisolated static func loadAudioSamples(from url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let srcFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else { return nil }

        let totalFrames = AVAudioFrameCount(min(Int64(AVAudioFrameCount.max), file.length))
        guard totalFrames > 0,
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: totalFrames)
        else { return nil }
        do {
            try file.read(into: srcBuffer)
        } catch {
            return nil
        }

        if srcFormat.sampleRate == 16_000, srcFormat.channelCount == 1,
           srcFormat.commonFormat == .pcmFormatFloat32,
           let ch = srcBuffer.floatChannelData?[0]
        {
            return Array(UnsafeBufferPointer(start: ch, count: Int(srcBuffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else { return nil }
        let ratio = 16_000.0 / max(1, srcFormat.sampleRate)
        let cap = AVAudioFrameCount((Double(srcBuffer.frameLength) * ratio).rounded(.up) + 512)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return nil }
        var supplied = false
        var err: NSError?
        converter.convert(to: outBuffer, error: &err) { _, outStatus in
            if supplied { outStatus.pointee = .noDataNow; return nil }
            supplied = true; outStatus.pointee = .haveData; return srcBuffer
        }
        guard err == nil, outBuffer.frameLength > 0, let outCh = outBuffer.floatChannelData?[0] else { return nil }
        let maxSamples = 16_000 * 60 * 20
        return Array(UnsafeBufferPointer(start: outCh, count: min(maxSamples, Int(outBuffer.frameLength))))
    }

    nonisolated static func writeCompressedM4A(samples: [Float], to url: URL) -> Bool {
        guard !samples.isEmpty,
              let inputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: 16_000,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: inputFormat,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channelData = buffer.floatChannelData?[0]
        else { return false }

        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                channelData.update(from: base, count: samples.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let file = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try file.write(from: buffer)
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    nonisolated static func writeWAV(samples: [Float], to url: URL) {
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
