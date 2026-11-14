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
        case installedOllama(modelName: String)
        case ollamaNotRunning
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var installedModelName: String?
    @ObservationIgnored private var pullTask: Task<Void, Never>?
    @ObservationIgnored private var downloadCoordinator: DirectDownloadCoordinator?

    static let defaultModelID = "hf.co/superwhisper/s1-mini-gguf:Q4_K_M"
    static let baseURL = URL(string: "http://localhost:11434")!

    var isInstalled: Bool {
        switch status {
        case .installedDirect, .installedOllama:
            return true
        default:
            return false
        }
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

        // 1. Direct local GGUF check (Default method)
        if let ggufURL = DictationLlamaServerManager.resolveGGUFModel() {
            installedModelName = ggufURL.path
            status = .installedDirect(path: ggufURL.path)
            return
        }

        // 2. Ollama check
        do {
            var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/tags"))
            request.timeoutInterval = 1.5
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                struct TagsResponse: Decodable {
                    struct ModelItem: Decodable {
                        let name: String
                    }
                    let models: [ModelItem]
                }
                let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
                if let match = decoded.models.first(where: { item in
                    let name = item.name.lowercased()
                    return name.contains("s1-mini") || name.contains("superwhisper/s1-mini-gguf")
                }) {
                    installedModelName = match.name
                    status = .installedOllama(modelName: match.name)
                    return
                }
            }
        } catch {
            // Ollama offline
        }

        installedModelName = nil
        status = .notInstalled
    }

    func cancelDownload() {
        pullTask?.cancel()
        pullTask = nil
        downloadCoordinator?.cancel()
        downloadCoordinator = nil
    }

    /// Download s1-mini-1.0.gguf directly from Hugging Face (Default standalone method)
    func download() {
        downloadDirectGGUF()
    }

    func downloadDirectGGUF() {
        cancelDownload()
        status = .downloading(progress: 0.0, statusText: "Connecting to Hugging Face...")

        let destination = DictationLlamaServerManager.defaultDestinationURL()
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

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
        coordinator.start(url: DictationLlamaServerManager.directHuggingFaceURL)
    }

    /// Pull model through local Ollama daemon
    func downloadOllama(model: String = DictationS1Downloader.defaultModelID) {
        cancelDownload()
        status = .downloading(progress: 0.0, statusText: "Starting download in Ollama...")

        pullTask = Task { [weak self] in
            guard let self else { return }
            do {
                let pullURL = Self.baseURL.appendingPathComponent("api/pull")
                var request = URLRequest(url: pullURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 600.0

                let body: [String: Any] = [
                    "model": model,
                    "stream": true
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }

                    if let err = json["error"] as? String {
                        throw NSError(domain: "OllamaPullError", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
                    }

                    let statusText = json["status"] as? String ?? "Downloading..."
                    var progress: Double = 0.0

                    if let total = json["total"] as? Int64,
                       let completed = json["completed"] as? Int64,
                       total > 0 {
                        progress = Double(completed) / Double(total)
                    }

                    self.status = .downloading(progress: progress, statusText: statusText)

                    if statusText == "success" {
                        self.status = .installedOllama(modelName: model)
                        self.installedModelName = model
                        break
                    }
                }

                await self.checkStatus()
            } catch is CancellationError {
                await self.checkStatus()
            } catch {
                self.status = .error(error.localizedDescription)
            }
        }
    }
}

private final class DirectDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @MainActor (Double, String) -> Void
    private let onCompletion: @MainActor (Result<URL, Error>) -> Void
    private var session: URLSession?
    private var task: URLSessionDownloadTask?

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

    func start(url: URL) {
        task = session?.downloadTask(with: url)
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
        if let error {
            Task { @MainActor in
                onCompletion(.failure(error))
            }
        }
    }
}
