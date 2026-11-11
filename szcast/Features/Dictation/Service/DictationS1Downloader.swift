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
        case installed(modelName: String)
        case ollamaNotRunning
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var installedModelName: String?
    @ObservationIgnored private var pullTask: Task<Void, Never>?

    static let defaultModelID = "hf.co/superwhisper/s1-mini-gguf:Q4_K_M"
    static let candidateRepositories = [
        "hf.co/superwhisper/s1-mini-gguf:Q4_K_M",
        "hf.co/superwhisper/s1-mini-gguf",
        "superwhisper/s1-mini-gguf"
    ]
    static let baseURL = URL(string: "http://localhost:11434")!

    var isInstalled: Bool {
        if case .installed = status { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = status { return true }
        return false
    }

    func checkStatus() async {
        if case .downloading = status { return }
        status = .checking
        do {
            var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/tags"))
            request.timeoutInterval = 2.5
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                status = .ollamaNotRunning
                installedModelName = nil
                return
            }

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
                status = .installed(modelName: match.name)
            } else {
                installedModelName = nil
                status = .notInstalled
            }
        } catch {
            status = .ollamaNotRunning
            installedModelName = nil
        }
    }

    func download(model: String = DictationS1Downloader.defaultModelID) {
        cancelDownload()
        status = .downloading(progress: 0.0, statusText: "Starting download...")

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
                        self.status = .installed(modelName: model)
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

    func cancelDownload() {
        pullTask?.cancel()
        pullTask = nil
    }

    func deleteModel(_ name: String) async {
        let deleteURL = Self.baseURL.appendingPathComponent("api/delete")
        var request = URLRequest(url: deleteURL)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["model": name]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
        await checkStatus()
    }
}
