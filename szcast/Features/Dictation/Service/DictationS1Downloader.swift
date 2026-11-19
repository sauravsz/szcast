import Foundation
import Observation

@MainActor
@Observable
final class DictationS1Downloader {
    enum Status: Equatable {
        case idle
        case checking
        case notInstalled
        case downloading(progress: Double, statusText: String)
        case installedDirect(path: String)
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var installedModelName: String?
    @ObservationIgnored private var downloadCoordinator: DirectDownloadCoordinator?

    static let defaultModelID = "hf.co/superwhisper/s1-mini-gguf:Q4_K_M"

    var isInstalled: Bool {
        if case .installedDirect = status { return true }
        return false
    }

    var isDirectGGUF: Bool {
        if case .installedDirect = status { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = status { return true }
        return false
    }

    func checkStatus() async {
        if case .downloading = status { return }
        status = .checking

        // Direct local GGUF check (Standalone method)
        if let ggufURL = DictationLlamaServerManager.resolveGGUFModel() {
            installedModelName = ggufURL.path
            status = .installedDirect(path: ggufURL.path)
            return
        }

        installedModelName = nil
        status = .notInstalled
    }

    func cancelDownload() {
        downloadCoordinator?.cancel()
        downloadCoordinator = nil
    }

    /// Download s1-mini-1.0.gguf directly from Hugging Face (Default standalone method)
    func download() {
        downloadDirectGGUF()
    }

    func downloadDirectGGUF() {
        cancelDownload()
        status = .downloading(progress: 0.0, statusText: "Connecting to model mirror...")

        let destination = DictationLlamaServerManager.defaultDestinationURL()
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let mirrors = [
            DictationLlamaServerManager.primaryGitHubURL,
            DictationLlamaServerManager.directHuggingFaceURL
        ]

        let coordinator = DirectDownloadCoordinator(
            onProgress: { [weak self] progress, statusText in
                self?.status = .downloading(progress: progress, statusText: statusText)
            },
            onCompletion: { [weak self] result in
                guard let self else { return }
                self.downloadCoordinator = nil
                switch result {
                case .success(let tempURL):
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }
                        try FileManager.default.moveItem(at: tempURL, to: destination)
                        Task { await self.checkStatus() }
                    } catch {
                        self.status = .error("Failed to install model: \(error.localizedDescription)")
                    }
                case .failure(let error):
                    if (error as NSError).code == NSURLErrorCancelled {
                        Task { await self.checkStatus() }
                    } else {
                        self.status = .error(error.localizedDescription)
                    }
                }
            }
        )

        self.downloadCoordinator = coordinator
        coordinator.start(urls: mirrors)
    }

    /// Import existing model file from local disk
    func importModelFile(from sourceURL: URL) async throws {
        let destination = DictationLlamaServerManager.defaultDestinationURL()
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        await checkStatus()
    }
}

private final class DirectDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @MainActor (Double, String) -> Void
    private let onCompletion: @MainActor (Result<URL, Error>) -> Void
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var urls: [URL] = []
    private var currentIndex: Int = 0
    private var resumeData: Data?
    private var retryCount: Int = 0

    init(
        onProgress: @escaping @MainActor (Double, String) -> Void,
        onCompletion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onCompletion = onCompletion
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 3600.0
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func start(urls: [URL]) {
        self.urls = urls
        self.currentIndex = 0
        self.retryCount = 0
        startCurrent()
    }

    func start(url: URL) {
        start(urls: [url])
    }

    private func startCurrent() {
        guard currentIndex < urls.count else {
            Task { @MainActor in
                self.onCompletion(.failure(NSError(domain: "DictationS1Download", code: 404, userInfo: [NSLocalizedDescriptionKey: "All download mirrors failed"])))
            }
            return
        }
        let url = urls[currentIndex]
        let mirrorName = url.host?.contains("github") == true ? "GitHub Mirror" : "Hugging Face"
        Task { @MainActor in
            self.onProgress(0.0, "Connecting to \(mirrorName)...")
        }

        if let resumeData {
            self.resumeData = nil
            task = session?.downloadTask(withResumeData: resumeData)
        } else {
            task = session?.downloadTask(with: url)
        }
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 484_219_808
        let progress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(expected)))
        let mbReceived = Double(totalBytesWritten) / (1024 * 1024)
        let mbTotal = Double(expected) / (1024 * 1024)
        let text = String(format: "%.1f MB / %.1f MB", mbReceived, mbTotal)
        Task { @MainActor in
            onProgress(progress, text)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if currentIndex + 1 < urls.count {
                currentIndex += 1
                retryCount = 0
                self.resumeData = nil
                startCurrent()
                return
            } else {
                Task { @MainActor in
                    self.onCompletion(.failure(NSError(domain: "DictationS1Download", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP \(http.statusCode)"])))
                }
                return
            }
        }

        // Validate file size (s1-mini-1.0.gguf is ~462MB; anything under 10MB is corrupt or an error page)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: location.path),
           let size = attrs[.size] as? UInt64, size < 10_000_000 {
            if currentIndex + 1 < urls.count {
                currentIndex += 1
                retryCount = 0
                self.resumeData = nil
                startCurrent()
                return
            } else {
                Task { @MainActor in
                    self.onCompletion(.failure(NSError(domain: "DictationS1Download", code: 422, userInfo: [NSLocalizedDescriptionKey: "Downloaded model file is incomplete or invalid"])))
                }
                return
            }
        }

        let tempTarget = FileManager.default.temporaryDirectory.appendingPathComponent("s1-mini-\(UUID().uuidString).gguf")
        do {
            if FileManager.default.fileExists(atPath: tempTarget.path) {
                try FileManager.default.removeItem(at: tempTarget)
            }
            try FileManager.default.moveItem(at: location, to: tempTarget)
            Task { @MainActor in
                onCompletion(.success(tempTarget))
            }
        } catch {
            Task { @MainActor in
                onCompletion(.failure(error))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError

        if nsError.code == NSURLErrorCancelled {
            Task { @MainActor in
                self.onCompletion(.failure(error))
            }
            return
        }

        // Check for resume data on socket drops
        if let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data, retryCount < 3 {
            retryCount += 1
            self.resumeData = data
            Task { @MainActor in
                self.onProgress(0.1, "Connection dropped. Resuming download...")
            }
            startCurrent()
            return
        }

        // Try next candidate mirror
        if currentIndex + 1 < urls.count {
            currentIndex += 1
            retryCount = 0
            self.resumeData = nil
            startCurrent()
            return
        }

        Task { @MainActor in
            self.onCompletion(.failure(error))
        }
    }
}
