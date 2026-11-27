import Foundation
import OSLog

@MainActor
final class DictationLlamaServerManager {
    static let shared = DictationLlamaServerManager()
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "LlamaServer")

    private var process: Process?
    private var runningPort: Int?
    private var runningModel: DictationTextModel?
    private var idleTask: Task<Void, Never>?
    private(set) var currentIdleRelease: DictationIdleRelease = .never

    static let defaultPort: Int = 51143
    static let primaryGitHubURL = URL(string: "https://github.com/sauravsz/szcast/releases/download/v1.1.2/s1-mini-1.0.gguf")!
    static let directHuggingFaceURL = URL(string: "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/34add00a48a2e5d24e5a4ee5405a99620a3a240c/s1-mini-q4_k_m.gguf")!

    func setIdleRelease(_ idleRelease: DictationIdleRelease) {
        currentIdleRelease = idleRelease
        if process?.isRunning == true {
            scheduleIdleShutdown(idleRelease: idleRelease)
        }
    }

    func startDaemon(idleRelease: DictationIdleRelease? = nil, settings: DictationS1Settings = .default) {
        Task { [weak self] in
            guard let self else { return }
            if !Self.isModelAvailable {
                _ = await Self.ensureModelDownloaded()
            }
            guard Self.isModelAvailable, Self.isBinaryAvailable else { return }
            _ = try? await self.ensureRunning(idleRelease: idleRelease ?? .never)
            self.prewarm(idleRelease: idleRelease ?? .never, settings: settings)
        }
    }

    func prewarm(idleRelease: DictationIdleRelease? = nil, settings: DictationS1Settings = .default) {
        guard isModelAvailable, isBinaryAvailable else { return }
        Task { [weak self] in
            guard let self else { return }
            if let baseURL = try? await self.ensureRunning(idleRelease: idleRelease) {
                let targetModel = Self.activeTextModel()
                let isS1 = targetModel == .s1Mini
                let chatEndpoint = baseURL.appendingPathComponent("v1/chat/completions")
                var request = URLRequest(url: chatEndpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("keep-alive", forHTTPHeaderField: "Connection")
                request.timeoutInterval = 10.0
                let userPrompt = DictationS1Settings.normalizedUserMessage(
                    controlLine: settings.controlLine,
                    transcript: "Hello",
                    isS1Mini: isS1
                )
                let prewarmPayload: [String: Any] = [
                    "model": targetModel.rawValue,
                    "messages": [
                        ["role": "system", "content": settings.effectiveSystemPrompt(for: "Hello", isS1Mini: isS1)],
                        ["role": "user", "content": userPrompt]
                    ],
                    "temperature": 0.0,
                    "max_tokens": 1
                ]
                request.httpBody = try? JSONSerialization.data(withJSONObject: prewarmPayload)
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }

    var isModelAvailable: Bool {
        Self.isModelAvailable
    }

    var isBinaryAvailable: Bool {
        Self.isBinaryAvailable
    }

    nonisolated static var isModelAvailable: Bool {
        resolveGGUFModel() != nil
    }

    nonisolated static var isBinaryAvailable: Bool {
        resolveServerBinary() != nil
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    nonisolated static func activeTextModel() -> DictationTextModel {
        UserDefaults.standard.string(forKey: "dictationLocalTextModel")
            .flatMap(DictationTextModel.init(rawValue:)) ?? .s1Mini
    }

    static func defaultDestinationURL(for model: DictationTextModel = .s1Mini) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if model == .s1Mini {
            return home.appendingPathComponent("Library/Application Support/szcast/Models/s1-mini/s1-mini-1.0.gguf")
        }
        return home.appendingPathComponent("Library/Application Support/szcast/Models/text/\(model.fileName)")
    }

    nonisolated static func destinationURL(for model: DictationTextModel) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if model == .s1Mini {
            return home.appendingPathComponent("Library/Application Support/szcast/Models/s1-mini/s1-mini-1.0.gguf")
        }
        return home.appendingPathComponent("Library/Application Support/szcast/Models/text/\(model.fileName)")
    }

    @discardableResult
    static func ensureModelDownloaded() async -> URL? {
        let active = activeTextModel()
        if let existing = resolveGGUFModel(for: active) {
            return existing
        }
        let destination = defaultDestinationURL(for: active)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        for mirror in active.downloadURLs {
            var request = URLRequest(url: mirror)
            request.timeoutInterval = 120.0
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            if let (tempURL, response) = try? await URLSession.shared.download(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    return destination
                } catch {
                    continue
                }
            }
        }
        return nil
    }

    nonisolated static func resolveGGUFModel(for model: DictationTextModel = activeTextModel()) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [URL] = [destinationURL(for: model)]
        if model == .s1Mini {
            candidates.append(contentsOf: [
                home.appendingPathComponent("Library/Application Support/szcast/Models/s1-mini-1.0.gguf"),
                home.appendingPathComponent("Library/Application Support/EnviousWispr/Models/s1-mini/s1-mini-1.0.gguf"),
                home.appendingPathComponent("Library/Application Support/EnviousWispr/Models/s1-mini.gguf"),
                AppPaths.caches().appendingPathComponent("Dictation/s1-mini/s1-mini-1.0.gguf")
            ])
        }
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64, size > 10_000_000 {
                return url
            }
        }
        return nil
    }

    nonisolated static func resolveServerBinary() -> URL? {
        if let bundled = Bundle.main.url(forResource: "llama-server", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let contentsResources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/llama-server")
        if FileManager.default.isExecutableFile(atPath: contentsResources.path) {
            return contentsResources
        }
        let candidates = [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func ensureRunning(idleRelease: DictationIdleRelease? = nil, forceRestart: Bool = false) async throws -> URL {
        if let idleRelease {
            currentIdleRelease = idleRelease
        }
        idleTask?.cancel()
        idleTask = nil

        let targetModel = Self.activeTextModel()
        let port = runningPort ?? Self.defaultPort
        let baseURL = URL(string: "http://127.0.0.1:\(port)")!

        if !forceRestart, process?.isRunning == true, runningModel == targetModel {
            scheduleIdleShutdown(idleRelease: currentIdleRelease)
            return baseURL
        }

        // Adopt an already-healthy server for the same model instead of colliding on the port.
        if !forceRestart, process == nil, await checkHealth(baseURL: baseURL),
           await runningModelMatches(baseURL: baseURL, expectedFileName: targetModel.fileName) {
            Self.logger.info("Adopted existing llama-server for \(targetModel.fileName) on \(baseURL.absoluteString)")
            self.runningPort = port
            self.runningModel = targetModel
            scheduleIdleShutdown(idleRelease: currentIdleRelease)
            return baseURL
        }

        stop()
        terminateOrphanListeners(on: port)

        guard let modelURL = Self.resolveGGUFModel(for: targetModel) else {
            throw NSError(
                domain: "DictationLlamaServer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(targetModel.fileName) not found"]
            )
        }
        guard let binaryURL = Self.resolveServerBinary() else {
            throw NSError(domain: "DictationLlamaServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "llama-server binary not found"])
        }

        let p = Process()
        p.executableURL = binaryURL
        p.arguments = [
            "-m", modelURL.path,
            "--host", "127.0.0.1",
            "--port", String(port),
            "-ngl", "99",
            "-np", "1",
            "-c", "1024",
            "-b", "512",
            "-ub", "512",
            "-fa", "on",
            "--cache-type-k", "q8_0",
            "--cache-type-v", "q8_0",
            "--cache-prompt",
            "--spec-type", "ngram-simple",
            "--reasoning", "off",
            "--jinja",
            "--chat-template-kwargs", "{\"enable_thinking\":false}"
        ]

        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice

        try p.run()
        self.process = p
        self.runningPort = port
        self.runningModel = targetModel

        // Wait up to 15s for health check (with -np 1, ready in ~0.5s; 15s budget prevents premature kill on slow disks)
        for i in 0..<75 {
            let sleepMs = i < 20 ? 100 : 200
            try? await Task.sleep(for: .milliseconds(sleepMs))
            if await checkHealth(baseURL: baseURL) {
                Self.logger.info("llama-server running on \(baseURL.absoluteString)")
                scheduleIdleShutdown(idleRelease: currentIdleRelease)
                return baseURL
            }
            if !p.isRunning {
                throw NSError(domain: "DictationLlamaServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "llama-server process exited"])
            }
        }

        if await checkHealth(baseURL: baseURL) {
            scheduleIdleShutdown(idleRelease: currentIdleRelease)
            return baseURL
        }

        p.terminate()
        throw NSError(domain: "DictationLlamaServer", code: 4, userInfo: [NSLocalizedDescriptionKey: "llama-server health check timed out"])
    }

    private func checkHealth(baseURL: URL) async -> Bool {
        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 0.5
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return false
        }
        return true
    }

    private func runningModelMatches(baseURL: URL, expectedFileName: String) async -> Bool {
        struct ModelsResponse: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/models"))
        request.timeoutInterval = 0.5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return false
        }
        return decoded.data.contains { $0.id.localizedCaseInsensitiveContains(expectedFileName) }
    }

    private func terminateOrphanListeners(on port: Int) {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-ti", ":\(port)", "-sTCP:LISTEN"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = FileHandle.nullDevice
        guard (try? lsof.run()) != nil else { return }
        lsof.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for token in out.split(whereSeparator: \.isWhitespace) {
            if let pid = Int32(token), pid > 0, pid != ProcessInfo.processInfo.processIdentifier {
                kill(pid, SIGTERM)
            }
        }
    }

    func scheduleIdleShutdown(idleRelease: DictationIdleRelease? = nil) {
        let release = idleRelease ?? currentIdleRelease
        idleTask?.cancel()
        idleTask = nil
        guard release != .never, release.rawValue > 0 else {
            return
        }
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(release.rawValue * 60))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func scheduleIdleShutdown(minutes: Int) {
        scheduleIdleShutdown(idleRelease: DictationIdleRelease(rawValue: minutes) ?? .never)
    }

    func stop() {
        idleTask?.cancel()
        idleTask = nil
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        runningPort = nil
        runningModel = nil
    }
}
