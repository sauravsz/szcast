@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import OSLog
@preconcurrency import Speech

private final class MemoryPressureMonitor: @unchecked Sendable {
    private let source: any DispatchSourceMemoryPressure

    init(onPressure: @escaping @Sendable () -> Void) {
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        src.setEventHandler(handler: onPressure)
        src.resume()
        self.source = src
    }

    deinit {
        source.cancel()
    }
}

@MainActor
@Observable
final class DictationModelStore {
    typealias Failure = DictationWire.Failure
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationModelStore")
    private static let customFoldersDefaultsKey = "dictationCustomModelFolders"

    private(set) var downloading: DictationModel?
    private(set) var downloadProgress: (received: Int64, total: Int64)?
    private(set) var removing: DictationModel?
    private(set) var downloadingSupport: DictationSupportModel?
    private(set) var supportDownloadProgress: (received: Int64, total: Int64)?
    private(set) var removingSupport: DictationSupportModel?
    private(set) var transcribing = false
    private(set) var loadedModel: DictationModel?
    private(set) var installedModels: Set<DictationModel> = []
    private(set) var installedSupportModels: Set<DictationSupportModel> = []
    private(set) var isPrewarming = false
    private(set) var customDirectories: [DictationModel: URL] = [:]
    @ObservationIgnored private var worker: DictationWorker?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?
    @ObservationIgnored private var prewarmID = UUID()
    @ObservationIgnored private var idleRelease: DictationIdleRelease
    @ObservationIgnored private var downloadTask: Task<Void, Error>?
    @ObservationIgnored private var downloadID: UUID?
    @ObservationIgnored private var supportDownloadTask: Task<Void, Error>?
    @ObservationIgnored private var supportDownloadID: UUID?
    @ObservationIgnored private let tokenProvider: (@Sendable () -> String?)?
    @ObservationIgnored private var memoryMonitor: MemoryPressureMonitor?
    private let root: URL
    private let makeWorker: () throws -> DictationWorker

    var isWorkerRunning: Bool {
        loadedModel == .speechAnalyzer || worker?.isRunning == true
    }

    private func getOrMakeWorker() throws -> DictationWorker {
        if let worker = self.worker, worker.isRunning {
            return worker
        }
        let newWorker = try makeWorker()
        self.worker = newWorker
        return newWorker
    }

    init(
        idleRelease: DictationIdleRelease,
        root: URL = AppPaths.caches().appending(path: "Dictation"),
        makeWorker: @escaping () throws -> DictationWorker = { try DictationWorker() },
        tokenProvider: (@Sendable () -> String?)? = nil
    ) {
        self.idleRelease = idleRelease
        self.root = root
        self.makeWorker = makeWorker
        self.tokenProvider = tokenProvider
        if let saved = UserDefaults.standard.dictionary(forKey: Self.customFoldersDefaultsKey) as? [String: String] {
            var loaded: [DictationModel: URL] = [:]
            for (rawKey, path) in saved {
                if let model = DictationModel(rawValue: rawKey) {
                    loaded[model] = URL(fileURLWithPath: path, isDirectory: true)
                }
            }
            self.customDirectories = loaded
        }
        refreshInstalledModels()
        self.memoryMonitor = MemoryPressureMonitor { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.transcribing, !self.isPrewarming, self.worker != nil else { return }
                Self.logger.notice("Releasing idle dictation worker under macOS memory pressure")
                await self.release()
            }
        }
    }

    func setCustomDirectory(_ directory: URL?, for model: DictationModel) {
        if let directory {
            customDirectories[model] = directory
        } else {
            customDirectories.removeValue(forKey: model)
        }
        let encoded = Dictionary(uniqueKeysWithValues: customDirectories.map { ($0.key.rawValue, $0.value.path) })
        UserDefaults.standard.set(encoded, forKey: Self.customFoldersDefaultsKey)
        refreshInstalledModels()
    }

    func customDirectory(for model: DictationModel) -> URL? {
        customDirectories[model]
    }

    func setIdleRelease(_ option: DictationIdleRelease) {
        idleRelease = option
        if worker != nil, !transcribing {
            scheduleRelease()
        } else {
            releaseTask?.cancel()
            releaseTask = nil
        }
    }

    func isInstalled(_ model: DictationModel) -> Bool {
        if model == .speechAnalyzer {
            if #available(macOS 26.0, *) { return true } else { return false }
        }
        return installedModels.contains(model)
    }

    func refreshInstalledModels() {
        var set = Set(
            DictationModel.allCases.filter { model in
                model != .speechAnalyzer && resolvedDirectory(for: model) != nil
            })
        if #available(macOS 26.0, *) {
            set.insert(.speechAnalyzer)
        }
        installedModels = set
        installedSupportModels = Set(
            DictationSupportModel.allCases.filter { supportModel in
                supportDirectoryIfInstalled(supportModel) != nil
            })
    }

    func isSupportInstalled(_ supportModel: DictationSupportModel) -> Bool {
        installedSupportModels.contains(supportModel)
    }

    func installedSupportSize(_ supportModel: DictationSupportModel) async -> Int64? {
        guard let directory = supportDirectoryIfInstalled(supportModel) else { return nil }
        return await directorySize(directory)
    }

    func installedSize(_ model: DictationModel) async -> Int64? {
        guard isInstalled(model) else { return nil }
        return await directorySize(directory(for: model))
    }

    private func directorySize(_ directory: URL) async -> Int64? {
        let task = Task.detached(priority: .utility) { () -> Int64? in
            guard
                let files = FileManager.default.enumerator(
                    at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            else { return nil }
            var size: Int64 = 0
            while let url = files.nextObject() as? URL {
                guard !Task.isCancelled else { return nil }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                    values.isRegularFile == true,
                    let bytes = values.fileSize
                else { continue }
                size += Int64(bytes)
            }
            return size
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func download(_ model: DictationModel) async throws {
        guard model != .speechAnalyzer else {
            refreshInstalledModels()
            return
        }
        guard downloading == nil, removing != model else { throw Failure.busy }
        guard !isInstalled(model) else { return }
        downloading = model
        let id = UUID()
        downloadID = id
        let destination = directory(for: model)
        let token = tokenProvider?()
        let task = Task.detached(priority: .utility) { [weak self] in
            try await DictationModelDownloader.download(model, destination: destination, token: token) {
                [weak self] received, total in
                Task { @MainActor [weak self] in
                    guard let self, self.downloadID == id else { return }
                    self.downloadProgress = (max(self.downloadProgress?.received ?? 0, received), total)
                }
            }
        }
        downloadTask = task
        defer { downloading = nil; downloadTask = nil; downloadID = nil; downloadProgress = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        installedModels.insert(model)
    }

    func cancelDownload() {
        downloadID = nil
        downloadTask?.cancel()
    }

    func delete(_ model: DictationModel) async throws {
        guard model != .speechAnalyzer else {
            setCustomDirectory(nil, for: model)
            return
        }
        guard !transcribing, removing == nil, downloading != model else { throw Failure.busy }
        removing = model
        defer { removing = nil }
        if loadedModel == model { await release() }
        if customDirectories[model] != nil {
            setCustomDirectory(nil, for: model)
        }
        let directory = directory(for: model)
        try await Task.detached(priority: .utility) {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }.value
        installedModels.remove(model)
    }

    func transcribe(
        _ samples: [Float], model: DictationModel, language: String? = nil
    ) async throws -> String {
        try await transcribeTimed(samples, model: model, language: language).text
    }

    func transcribeTimed(
        _ samples: [Float],
        model: DictationModel,
        language: String? = nil,
        useVAD: Bool = true,
        diarizeSpeakers: Int? = nil
    ) async throws -> TimedTranscript {
        try Task.checkCancellation()
        guard !samples.isEmpty else { return TimedTranscript(text: "") }
        guard !transcribing, removing != model else { throw Failure.busy }
        guard isInstalled(model) else { throw Failure.notInstalled }
        releaseTask?.cancel()
        releaseTask = nil

        if let task = prewarmTask {
            await task.value
        }

        if model == .speechAnalyzer {
            transcribing = true
            loadedModel = .speechAnalyzer
            defer { transcribing = false; scheduleRelease() }
            if #available(macOS 26.0, *) {
                return try await Self.transcribeWithSpeechAnalyzer(samples: samples, language: language)
            }
            throw Failure.unavailable
        }

        transcribing = true
        defer { transcribing = false; scheduleRelease() }
        do {
            if loadedModel != model || worker?.isRunning != true {
                await release()
            }
            try Task.checkCancellation()
            var worker = try getOrMakeWorker()
            let vadDir = useVAD ? supportDirectoryIfInstalled(.sileroVAD) : nil
            let diarDir = diarizeSpeakers != nil ? supportDirectoryIfInstalled(.speakerDiarization) : nil
            let sendLanguage = (model.isQwen || model.isSraVaani || model.isSpecialized) ? language : nil

            let ranges = samples.count <= DictationWire.maximumSamples
                ? [0..<samples.count]
                : DictationAudioChunks.ranges(in: samples, maximum: DictationWire.maximumSamples)

            var allWords = [TranscriptWord]()
            var allSegments = [TranscriptSegment]()
            var texts = [String]()
            var retriedCrashedWorker = false

            for range in ranges {
                try Task.checkCancellation()
                let chunkSamples = Array(samples[range])
                var part: TimedTranscript?
                while part == nil {
                    let request = DictationWire.Request(
                        id: UUID(),
                        model: model,
                        directory: directory(for: model),
                        sampleCount: chunkSamples.count,
                        language: sendLanguage,
                        useVAD: useVAD,
                        vadDirectory: vadDir,
                        diarizeSpeakers: diarizeSpeakers,
                        diarizationDirectory: diarDir
                    )
                    let activeWorker = worker
                    do {
                        part = try await activeWorker.transcribeTimed(chunkSamples, request: request) { [weak self] in
                            guard let self, self.worker === activeWorker, self.transcribing else { return }
                            self.loadedModel = model
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Single auto-retry respawn if helper process crashed mid-chunk under memory pressure.
                        guard !retriedCrashedWorker, !Task.isCancelled else { throw error }
                        retriedCrashedWorker = true
                        Self.logger.warning("Dictation worker failed mid-chunk; respawning for one retry")
                        await release()
                        worker = try getOrMakeWorker()
                    }
                }
                guard let resolvedPart = part else { continue }
                let offset = Double(range.lowerBound) / Double(DictationWire.sampleRate)
                let cleanPart = resolvedPart.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanPart.isEmpty { texts.append(cleanPart) }
                Self.appendShifted(resolvedPart, offset: offset, words: &allWords, segments: &allSegments)
            }
            let fullText = texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return TimedTranscript(text: fullText, words: allWords, segments: allSegments)
        } catch {
            await release()
            throw error
        }
    }

    @available(macOS 26.0, *)
    private static func transcribeWithSpeechAnalyzer(
        samples: [Float],
        language: String?
    ) async throws -> TimedTranscript {
        let totalStart = CFAbsoluteTimeGetCurrent()
        let requestedLocale: Locale = {
            let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty, trimmed.lowercased() != "auto" else { return Locale(identifier: "en-US") }
            switch trimmed.lowercased() {
            case "english": return Locale(identifier: "en-US")
            case "hindi", "hinglish": return Locale(identifier: "hi-IN")
            case "bengali", "banglish": return Locale(identifier: "bn-IN")
            case "cantonese": return Locale(identifier: "zh-HK")
            case "chinese": return Locale(identifier: "zh-CN")
            case "spanish": return Locale(identifier: "es-ES")
            case "french": return Locale(identifier: "fr-FR")
            case "german": return Locale(identifier: "de-DE")
            case "japanese": return Locale(identifier: "ja-JP")
            case "korean": return Locale(identifier: "ko-KR")
            default: return Locale(identifier: trimmed)
            }
        }()

        let installed = await DictationTranscriber.installedLocales
        let effectiveLocale: Locale
        if let exact = installed.first(where: { $0.identifier == requestedLocale.identifier }) {
            effectiveLocale = exact
        } else if let langMatch = installed.first(where: { $0.language.languageCode == requestedLocale.language.languageCode }) {
            effectiveLocale = langMatch
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) {
            effectiveLocale = supported
        } else {
            effectiveLocale = Locale(identifier: "en-US")
        }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(DictationWire.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw Failure.unavailable
        }

        let module = DictationTranscriber(locale: effectiveLocale, preset: .timeIndexedLongDictation)
        guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module],
            considering: sourceFormat
        ) else {
            throw Failure.unavailable
        }
        let converter = (sourceFormat == targetFormat) ? nil : AVAudioConverter(from: sourceFormat, to: targetFormat)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(64))
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: targetFormat)

        let collector = Task<[TranscriptSegment], Error> {
            var collectedSegments = [TranscriptSegment]()
            for try await result in module.results where result.isFinal {
                let piece = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !piece.isEmpty else { continue }
                let startSec = result.range.start.seconds.isFinite ? max(0, result.range.start.seconds) : 0
                let durSec = result.range.duration.seconds.isFinite ? max(0, result.range.duration.seconds) : 0
                collectedSegments.append(
                    TranscriptSegment(speaker: "", text: piece, start: startSec, end: startSec + durSec)
                )
            }
            return collectedSegments
        }

        let feedTask = Task.detached(priority: .userInitiated) {
            let chunkFrames = 32_000
            var offset = 0
            while offset < samples.count {
                let count = min(chunkFrames, samples.count - offset)
                if let inBuf = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(count)),
                   let dst = inBuf.floatChannelData?[0]
                {
                    inBuf.frameLength = AVAudioFrameCount(count)
                    samples.withUnsafeBufferPointer { src in
                        if let base = src.baseAddress {
                            dst.update(from: base.advanced(by: offset), count: count)
                        }
                    }
                    let sendBuf: AVAudioPCMBuffer
                    if let converter {
                        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
                        let cap = AVAudioFrameCount((Double(count) * ratio).rounded(.up) + 256)
                        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else {
                            offset += count
                            continue
                        }
                        var supplied = false
                        var err: NSError?
                        converter.convert(to: outBuf, error: &err) { _, outStatus in
                            if supplied { outStatus.pointee = .noDataNow; return nil }
                            supplied = true; outStatus.pointee = .haveData; return inBuf
                        }
                        guard err == nil, outBuf.frameLength > 0 else {
                            offset += count
                            continue
                        }
                        sendBuf = outBuf
                    } else {
                        sendBuf = inBuf
                    }
                    nonisolated(unsafe) let box = sendBuf
                    continuation.yield(AnalyzerInput(buffer: box))
                }
                offset += count
            }
            continuation.finish()
        }

        _ = try await analyzer.analyzeSequence(stream)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        await feedTask.value
        let segments = try await collector.value
        let fullText = segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000
        let timings = DictationStageTimings(vadMs: 0, asrMs: totalMs, diarizationMs: 0, totalMs: totalMs)
        return TimedTranscript(text: fullText, words: [], segments: segments, timings: timings)
    }

    private static func appendShifted(
        _ part: TimedTranscript,
        offset: TimeInterval,
        words: inout [TranscriptWord],
        segments: inout [TranscriptSegment]
    ) {
        for word in part.words {
            words.append(TranscriptWord(
                text: word.text,
                start: word.start + offset,
                end: word.end + offset,
                confidence: word.confidence
            ))
        }
        for seg in part.segments {
            var shiftedWords = [TranscriptWord]()
            shiftedWords.reserveCapacity(seg.words.count)
            for word in seg.words {
                shiftedWords.append(TranscriptWord(
                    text: word.text,
                    start: word.start + offset,
                    end: word.end + offset,
                    confidence: word.confidence
                ))
            }
            segments.append(TranscriptSegment(
                id: seg.id,
                speaker: seg.speaker,
                text: seg.text,
                start: seg.start + offset,
                end: seg.end + offset,
                words: shiftedWords
            ))
        }
    }

    func supportDirectoryIfInstalled(_ supportModel: DictationSupportModel) -> URL? {
        let candidateRoots = [
            root,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FluidAudio/Models"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/EnviousWispr/Models")
        ]
        for candidateRoot in candidateRoots {
            for folder in supportModel.possibleFolderNames {
                let candidate = candidateRoot.appendingPathComponent(folder)
                if supportModel.requiredFiles.allSatisfy({
                    FileManager.default.fileExists(atPath: candidate.appendingPathComponent($0).path)
                }) {
                    return candidate
                }
            }
        }
        return nil
    }

    func downloadSupportModel(_ supportModel: DictationSupportModel) async throws -> URL {
        if let existing = supportDirectoryIfInstalled(supportModel) {
            installedSupportModels.insert(supportModel)
            return existing
        }
        guard downloadingSupport == nil, removingSupport != supportModel else { throw Failure.busy }
        downloadingSupport = supportModel
        let id = UUID()
        supportDownloadID = id
        let dest = root.appendingPathComponent(supportModel.folderName)
        let token = tokenProvider?()
        let task = Task.detached(priority: .utility) { [weak self] in
            try await DictationModelDownloader.download(supportModel, destination: dest, token: token) {
                [weak self] received, total in
                Task { @MainActor [weak self] in
                    guard let self, self.supportDownloadID == id else { return }
                    self.supportDownloadProgress = (max(self.supportDownloadProgress?.received ?? 0, received), total)
                }
            }
        }
        supportDownloadTask = task
        defer {
            downloadingSupport = nil
            supportDownloadTask = nil
            supportDownloadID = nil
            supportDownloadProgress = nil
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        installedSupportModels.insert(supportModel)
        return dest
    }

    func cancelSupportDownload() {
        supportDownloadID = nil
        supportDownloadTask?.cancel()
    }

    func deleteSupportModel(_ supportModel: DictationSupportModel) async throws {
        guard !transcribing, removingSupport == nil, downloadingSupport != supportModel else { throw Failure.busy }
        removingSupport = supportModel
        defer { removingSupport = nil }
        await release()
        if let dir = supportDirectoryIfInstalled(supportModel) {
            try await Task.detached(priority: .utility) {
                if FileManager.default.fileExists(atPath: dir.path) {
                    try FileManager.default.removeItem(at: dir)
                }
            }.value
        }
        installedSupportModels.remove(supportModel)
    }

    func ensurePrewarmed(_ model: DictationModel) {
        refreshInstalledModels()
        if isInstalled(model) {
            prewarm(model)
        } else {
            Task { [weak self] in
                guard let self else { return }
                try? await self.download(model)
                self.refreshInstalledModels()
                if self.isInstalled(model) {
                    self.prewarm(model)
                }
            }
        }
    }

    func prewarm(_ model: DictationModel) {
        guard model != .speechAnalyzer else {
            loadedModel = .speechAnalyzer
            isPrewarming = false
            return
        }
        guard isInstalled(model), !transcribing else { return }
        releaseTask?.cancel()
        releaseTask = nil
        if loadedModel == model, let worker = self.worker, worker.isRunning {
            isPrewarming = false
            scheduleRelease()
            return
        }
        let id = UUID()
        prewarmID = id
        let previousTask = prewarmTask
        previousTask?.cancel()
        if loadedModel != model {
            let oldWorker = self.worker
            self.worker = nil
            self.loadedModel = nil
            oldWorker?.terminate()
            if let oldWorker {
                Task.detached(priority: .utility) { await oldWorker.stop() }
            }
        }
        isPrewarming = true
        prewarmTask = Task { [weak self] in
            _ = await previousTask?.value
            guard let self, self.prewarmID == id, !self.transcribing, !Task.isCancelled else {
                if let self, self.prewarmID == id {
                    self.isPrewarming = false
                    self.prewarmTask = nil
                }
                return
            }
            defer {
                if self.prewarmID == id {
                    self.isPrewarming = false
                    self.prewarmTask = nil
                }
            }
            do {
                let worker = try self.getOrMakeWorker()
                if self.loadedModel != model {
                    let request = DictationWire.Request(
                        id: UUID(),
                        model: model,
                        directory: self.directory(for: model),
                        sampleCount: 0,
                        language: nil,
                        prewarmOnly: true
                    )
                    _ = try await worker.transcribeTimed([], request: request) { [weak self] in
                        guard let self, self.prewarmID == id, self.worker === worker else { return }
                        self.loadedModel = model
                    }
                    if self.prewarmID == id, self.worker === worker {
                        self.loadedModel = model
                    }
                }
                if self.prewarmID == id {
                    self.scheduleRelease()
                }
            } catch is CancellationError {
                // Cancellation when switching models or starting dictation is expected.
            } catch {
                if self.prewarmID == id {
                    let staleWorker = self.worker
                    self.worker = nil
                    self.loadedModel = nil
                    staleWorker?.terminate()
                    if let staleWorker {
                        Task.detached(priority: .utility) { await staleWorker.stop() }
                    }
                }
            }
        }
    }

    func release() async {
        releaseTask?.cancel()
        releaseTask = nil
        prewarmID = UUID()
        prewarmTask?.cancel()
        prewarmTask = nil
        isPrewarming = false
        let worker = self.worker
        self.worker = nil
        loadedModel = nil
        await worker?.stop()
    }

    func stop() async {
        downloadTask?.cancel()
        supportDownloadTask?.cancel()
        try? await downloadTask?.value
        try? await supportDownloadTask?.value
        await release()
    }

    func prepareForTermination() {
        downloadTask?.cancel()
        supportDownloadTask?.cancel()
        prewarmTask?.cancel()
        worker?.terminate()
    }

    private func scheduleRelease() {
        releaseTask?.cancel()
        guard worker != nil, idleRelease != .never else { releaseTask = nil; return }
        let interval = Duration.seconds(idleRelease.rawValue * 60)
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: interval, tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            guard let self, !self.transcribing else { return }
            await self.release()
        }
    }

    func resolvedDirectory(for model: DictationModel) -> URL? {
        guard model != .speechAnalyzer else { return nil }
        if let customDir = customDirectories[model] {
            let valid = model.requiredFiles.allSatisfy { file in
                FileManager.default.fileExists(atPath: customDir.appendingPathComponent(file).path)
            }
            if valid { return customDir }
        }
        let candidateRoots = [
            root,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FluidAudio/Models"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/EnviousWispr/Models")
        ]
        for candidateRoot in candidateRoots {
            for folder in model.possibleFolderNames {
                let candidateDir = candidateRoot.appendingPathComponent(folder)
                let allFilesExist = model.requiredFiles.allSatisfy { file in
                    FileManager.default.fileExists(atPath: candidateDir.appendingPathComponent(file).path)
                }
                if allFilesExist {
                    return candidateDir
                }
            }
        }
        return nil
    }

    private func directory(for model: DictationModel) -> URL {
        if let resolved = resolvedDirectory(for: model) {
            return resolved
        }
        return root.appendingPathComponent(model.folderName)
    }
}
