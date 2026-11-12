import Foundation
import OSLog

actor DictationS1Polisher {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationS1Polish")

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 5.0
        return URLSession(configuration: config)
    }()

    /// Check if model identifier corresponds to S1-mini.
    static func isS1Mini(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        let repository = "hf.co/superwhisper/s1-mini-gguf"
        return lower == repository || lower.hasPrefix(repository + ":") || lower.contains("s1-mini")
    }

    /// Assembles ChatML frame for S1-mini with an explicitly closed empty think block.
    /// This fixes the bug where Ollama's default GGUF template ends in an unclosed <think> tag,
    /// causing the model to output empty responses over standard /api/chat or /v1/chat/completions.
    static func makeRawPrompt(systemPrompt: String, userMessage: String) -> String {
        let assistantPrefix = "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        return "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(userMessage)<|im_end|>\n\(assistantPrefix)"
    }

    func polish(
        _ transcript: String,
        settings: DictationS1Settings,
        endpointURL: URL? = nil,
        model: String = "hf.co/superwhisper/s1-mini-gguf:Q4_K_M"
    ) async -> String {
        guard settings.enabled, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return transcript
        }

        let userMessage = "\(settings.controlLine)\n\(transcript)"

        // Priority 1 (DEFAULT): Direct local s1-mini-1.0.gguf via embedded/managed llama-server
        if let llamaServerURL = try? await DictationLlamaServerManager.shared.ensureRunning(idleRelease: settings.idleRelease) {
            let chatEndpoint = llamaServerURL.appendingPathComponent("v1/chat/completions")
            if let output = try? await sendChatRequest(
                model: "s1-mini",
                systemPrompt: DictationS1Settings.systemPrompt,
                userMessage: userMessage,
                endpointURL: chatEndpoint
            ) {
                return output
            }
        }

        // Priority 2: Local Ollama with S1-mini ChatML raw transport (or caller-specified endpointURL)
        let targetURL = endpointURL ?? URL(string: "http://localhost:11434")!
        let baseURL = Self.normalizedBaseURL(targetURL)
        let effectiveModel = await resolveModel(preferred: model, baseURL: baseURL)

        do {
            if Self.isS1Mini(effectiveModel) {
                // S1-mini raw transport with closed think block
                if let output = try await sendRawGenerateRequest(
                    model: effectiveModel,
                    systemPrompt: DictationS1Settings.systemPrompt,
                    userMessage: userMessage,
                    baseURL: baseURL
                ) {
                    return output
                }
            } else {
                // General fallback model (e.g. llama3.2:3b) via standard chat completions
                let chatURL = baseURL.appendingPathComponent("v1/chat/completions")
                if let output = try await sendChatRequest(
                    model: effectiveModel,
                    systemPrompt: DictationS1Settings.generalSystemPrompt,
                    userMessage: transcript,
                    endpointURL: chatURL
                ) {
                    return output
                }
            }
        } catch {
            Self.logger.notice("S1 polish unavailable or timed out; using deterministic text: \(error.localizedDescription)")
        }

        return transcript
    }

    static func normalizedBaseURL(_ url: URL) -> URL {
        let path = url.path
        if path.hasSuffix("/v1/chat/completions") || path.hasSuffix("/api/chat") || path.hasSuffix("/api/generate") {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.path = ""
            return comps?.url ?? url
        }
        return url
    }

    private func sendRawGenerateRequest(
        model: String,
        systemPrompt: String,
        userMessage: String,
        baseURL: URL
    ) async throws -> String? {
        let generateURL = baseURL.appendingPathComponent("api/generate")
        let prompt = Self.makeRawPrompt(systemPrompt: systemPrompt, userMessage: userMessage)

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "raw": true,
            "stream": false,
            "keep_alive": "60m",
            "options": [
                "num_predict": 512,
                "temperature": 0.1,
                "stop": ["<|im_end|>"]
            ]
        ]

        var request = URLRequest(url: generateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4.0
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            return nil
        }

        let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sendChatRequest(
        model: String,
        systemPrompt: String,
        userMessage: String,
        endpointURL: URL
    ) async throws -> String? {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct RequestBody: Encodable {
            let model: String
            let messages: [Message]
            let temperature: Double
            let stream: Bool
            let max_tokens: Int
        }

        struct ResponseBody: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable {
                    let content: String
                }
                let message: Msg
            }
            let choices: [Choice]
        }

        let cap = max(32, min(384, userMessage.split(separator: " ").count * 3))
        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userMessage)
            ],
            temperature: 0.1,
            stream: false,
            max_tokens: cap
        )

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4.0
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await Self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        if let output = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
            return output
        }
        return nil
    }

    private func resolveModel(preferred: String, baseURL: URL) async -> String {
        let tagsURL = baseURL.appendingPathComponent("api/tags")
        struct TagsResponse: Decodable {
            struct TagModel: Decodable {
                let name: String
            }
            let models: [TagModel]
        }
        var request = URLRequest(url: tagsURL)
        request.timeoutInterval = 1.5
        guard let (data, response) = try? await Self.session.data(for: request),
              let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            return preferred
        }

        if decoded.models.contains(where: { $0.name == preferred }) {
            return preferred
        }

        if let s1Match = decoded.models.first(where: { Self.isS1Mini($0.name) }) {
            return s1Match.name
        }

        let preferredFallbacks = ["ministral-3:3b", "qwen3.5:2b", "phi4-mini:3.8b", "llama3.2:3b", "smollm3"]
        for pref in preferredFallbacks {
            if let match = decoded.models.first(where: { $0.name.localizedCaseInsensitiveContains(pref) }) {
                return match.name
            }
        }
        return decoded.models.first?.name ?? preferred
    }
}
