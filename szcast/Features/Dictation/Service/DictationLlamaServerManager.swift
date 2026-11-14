import Foundation
import OSLog

@MainActor
final class DictationLlamaServerManager {
    static let shared = DictationLlamaServerManager()
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "LlamaServer")

    private var process: Process?
    private var runningPort: Int?
    private var idleTask: Task<Void, Never>?
    private(set) var currentIdleRelease: DictationIdleRelease = .never

    static let defaultPort: Int = 51143
    static let directHuggingFaceURL = URL(string: "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/34add00a48a2e5d24e5a4ee5405a99620a3a240c/s1-mini-q4_k_m.gguf")!

    func setIdleRelease(_ idleRelease: DictationIdleRelease) {
        currentIdleRelease = idleRelease
        if process?.isRunning == true {
            scheduleIdleShutdown(idleRelease: idleRelease)
        }
    }

    func prewarm(idleRelease: DictationIdleRelease? = nil) {
        guard isModelAvailable, isBinaryAvailable else { return }
        Task { [weak self] in
            guard let self else { return }
            if let baseURL = try? await self.ensureRunning(idleRelease: idleRelease) {
                // Background KV-cache prewarming: prime the system prompt and control line into llama-server's KV cache
                let chatEndpoint = baseURL.appendingPathComponent("v1/chat/completions")
                var request = URLRequest(url: chatEndpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("keep-alive", forHTTPHeaderField: "Connection")
                request.timeoutInterval = 2.0
                let prewarmPayload: [String: Any] = [
                    "model": "s1-mini",
                    "messages": [
                        ["role": "system", "content": DictationS1Settings.systemPrompt],
                        ["role": "user", "content": "\(DictationS1Settings.default.controlLine)\nHello"]
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
        Self.resolveGGUFModel() != nil
    }

    var isBinaryAvailable: Bool {
        Self.resolveServerBinary() != nil
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    static func defaultDestinationURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/szcast/Models/s1-mini/s1-mini-1.0.gguf")
    }

    static func resolveGGUFModel() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Application Support/szcast/Models/s1-mini/s1-mini-1.0.gguf"),
            home.appendingPathComponent("Library/Application Support/szcast/Models/s1-mini-1.0.gguf"),
            home.appendingPathComponent("Library/Application Support/EnviousWispr/Models/s1-mini/s1-mini-1.0.gguf"),
            home.appendingPathComponent("Library/Application Support/EnviousWispr/Models/s1-mini.gguf"),
            AppPaths.caches().appendingPathComponent("Dictation/s1-mini/s1-mini-1.0.gguf")
        ]
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    static func resolveServerBinary() -> URL? {
        if let bundled = Bundle.main.url(forResource: "llama-server", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let contentsResources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/llama-server")
        if FileManager.default.isExecutableFile(atPath: contentsResources.path) {
            return contentsResources
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("AIOS/Github Repos/szcast/szcast/Resources/llama-server").path,
            home.appendingPathComponent(".lmstudio/extensions/backends/llama.cpp-mac-arm64-apple-metal-advsimd-2.60.0/llama-server").path,
            home.appendingPathComponent(".lmstudio/extensions/backends/llama.cpp-mac-arm64-apple-metal-advsimd-2.55.0/llama-server").path,
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

        let port = runningPort ?? Self.defaultPort
        let baseURL = URL(string: "http://127.0.0.1:\(port)")!

        if !forceRestart, process?.isRunning == true {
            scheduleIdleShutdown(idleRelease: currentIdleRelease)
            return baseURL
        }

        stop()

        guard let modelURL = Self.resolveGGUFModel() else {
            throw NSError(domain: "DictationLlamaServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "s1-mini-1.0.gguf not found"])
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
            "-c", "8192",
            "-fa", "on",
            "--cache-type-k", "q8_0",
            "--cache-type-v", "q8_0",
            "--jinja",
            "--chat-template-kwargs", "{\"enable_thinking\":false}"
        ]

        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice

        try p.run()
        self.process = p
        self.runningPort = port

        // Wait up to 5s for health check
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(200))
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
    }
}
