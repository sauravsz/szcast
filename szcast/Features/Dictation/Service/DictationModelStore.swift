import Foundation

@MainActor
@Observable
final class DictationModelStore {
    typealias Failure = DictationWire.Failure

    private(set) var downloading: DictationModel?
    private(set) var downloadProgress: (received: Int64, total: Int64)?
    private(set) var removing: DictationModel?
    private(set) var transcribing = false
    private(set) var loadedModel: DictationModel?
    private(set) var installedModels: Set<DictationModel> = []
    private(set) var isPrewarming = false
    @ObservationIgnored private var worker: DictationWorker?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?
    @ObservationIgnored private var idleRelease: DictationIdleRelease
    @ObservationIgnored private var downloadTask: Task<Void, Error>?
    @ObservationIgnored private var downloadID: UUID?
    @ObservationIgnored private let tokenProvider: (@Sendable () -> String?)?
    private let root: URL
    private let makeWorker: () throws -> DictationWorker

    var isWorkerRunning: Bool {
        worker?.isRunning == true
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
        refreshInstalledModels()
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
        installedModels.contains(model)
    }

    func refreshInstalledModels() {
        installedModels = Set(
            DictationModel.allCases.filter { model in
                resolvedDirectory(for: model) != nil
            })
    }

    func installedSize(_ model: DictationModel) async -> Int64? {
        guard isInstalled(model) else { return nil }
        let directory = directory(for: model)
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
        guard !transcribing, removing == nil, downloading != model else { throw Failure.busy }
        removing = model
        defer { removing = nil }
        if loadedModel == model { await release() }
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
        try Task.checkCancellation()
        guard !transcribing, removing != model else { throw Failure.busy }
        guard isInstalled(model) else { throw Failure.notInstalled }
        releaseTask?.cancel()
        releaseTask = nil

        // If background prewarming is currently in flight, await it so we don't abort it and trigger a cold-restart
        if let task = prewarmTask {
            await task.value
        }

        transcribing = true
        defer { transcribing = false; scheduleRelease() }
        do {
            if loadedModel != model || worker?.isRunning != true {
                await release()
            }
            try Task.checkCancellation()
            let worker = try getOrMakeWorker()
            let request = DictationWire.Request(
                id: UUID(), model: model, directory: directory(for: model),
                sampleCount: samples.count, language: (model.isQwen || model.isSraVaani || model.isSpecialized) ? language : nil)
            let text = try await worker.transcribe(samples, request: request) { [weak self] in
                guard let self, self.worker === worker, self.transcribing else { return }
                self.loadedModel = model
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            await release()
            throw error
        }
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
        guard isInstalled(model), !transcribing else { return }
        releaseTask?.cancel()
        releaseTask = nil
        if loadedModel == model, let worker = self.worker, worker.isRunning {
            return
        }
        prewarmTask?.cancel()
        isPrewarming = true
        prewarmTask = Task { [weak self] in
            guard let self, !self.transcribing else { return }
            defer {
                self.isPrewarming = false
                self.prewarmTask = nil
            }
            do {
                if self.loadedModel != model || self.worker?.isRunning != true {
                    let oldWorker = self.worker
                    self.worker = nil
                    self.loadedModel = nil
                    await oldWorker?.stop()
                }
                guard !self.transcribing, !Task.isCancelled else { return }
                let worker = try self.getOrMakeWorker()
                if self.loadedModel != model {
                    let dummySamples = [Float](repeating: 0.0, count: 16_000)
                    let request = DictationWire.Request(
                        id: UUID(), model: model, directory: self.directory(for: model),
                        sampleCount: dummySamples.count, language: nil
                    )
                    _ = try await worker.transcribe(dummySamples, request: request) { [weak self] in
                        guard let self, self.worker === worker else { return }
                        self.loadedModel = model
                    }
                    self.loadedModel = model
                }
                self.scheduleRelease()
            } catch is CancellationError {
                // If prewarming was canceled by an in-flight transcribe or explicit release, keep state clean
            } catch {
                let staleWorker = self.worker
                self.worker = nil
                self.loadedModel = nil
                await staleWorker?.stop()
            }
        }
    }

    func release() async {
        releaseTask?.cancel()
        releaseTask = nil
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
        try? await downloadTask?.value
        await release()
    }

    func prepareForTermination() {
        downloadTask?.cancel()
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
