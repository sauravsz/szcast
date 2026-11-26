import Foundation
import OSLog

actor DictationS1Polisher {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationS1Polish")

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 120.0
        return URLSession(configuration: config)
    }()

    /// Clean, unquote, un-think, and capitalize polished output.
    static func cleanOutput(_ raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("<think>") {
            trimmed = trimmed.replacingOccurrences(of: #"(?s)<think>.*?(?:</think>|$)\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("```") {
            trimmed = trimmed.replacingOccurrences(of: #"^```[a-zA-Z]*\n?"#, with: "", options: .regularExpression)
            trimmed = trimmed.replacingOccurrences(of: #"\n?```$"#, with: "", options: .regularExpression)
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2) ||
           (trimmed.hasPrefix("“") && trimmed.hasSuffix("”") && trimmed.count >= 2) {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        trimmed = trimmed.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
        if let firstLetterIndex = trimmed.firstIndex(where: { $0.isLetter }) {
            trimmed.replaceSubrange(firstLetterIndex...firstLetterIndex, with: String(trimmed[firstLetterIndex]).uppercased())
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Check if model identifier corresponds to S1-mini.
    static func isS1Mini(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        let repository = "hf.co/superwhisper/s1-mini-gguf"
        return lower == repository || lower.hasPrefix(repository + ":") || lower.contains("s1-mini")
    }

    /// Assembles ChatML frame for S1-mini with an explicitly closed empty think block.
    /// This fixes the bug where S1-mini GGUF templates end in an unclosed <think> tag,
    /// causing the model to output empty responses over standard /api/chat or /v1/chat/completions.
    static func makeRawPrompt(systemPrompt: String, userMessage: String) -> String {
        let assistantPrefix = "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        return "<|im_start|>system\n\(systemPrompt)<|im_end|>\n<|im_start|>user\n\(userMessage)<|im_end|>\n\(assistantPrefix)"
    }

    func polish(
        _ transcript: String,
        settings: DictationS1Settings,
        vocabularyTerms: [String] = [],
        surroundingContext: String? = nil,
        endpointURL: URL? = nil,
        model: String = "s1-mini"
    ) async -> String {
        guard settings.enabled, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return transcript
        }

        let userMessage = DictationS1Settings.normalizedUserMessage(
            controlLine: settings.controlLine,
            transcript: transcript,
            vocabularyTerms: vocabularyTerms,
            surroundingContext: surroundingContext
        )
        let transcriptWordCount = transcript.split(separator: " ").count
        let effectiveSystemPrompt = settings.effectiveSystemPrompt(for: transcript)

        // Custom endpoint (e.g. for testing)
        if let customEndpoint = endpointURL {
            let chatEndpoint = customEndpoint.path.hasSuffix("/v1/chat/completions") ? customEndpoint : customEndpoint.appendingPathComponent("v1/chat/completions")
            if let output = try? await sendChatRequest(
                model: model,
                systemPrompt: effectiveSystemPrompt,
                userMessage: userMessage,
                transcriptWordCount: transcriptWordCount,
                endpointURL: chatEndpoint
            ) {
                return output
            }
            return transcript
        }

        // Direct local s1-mini-1.0.gguf via embedded/managed llama-server
        guard DictationLlamaServerManager.isModelAvailable && DictationLlamaServerManager.isBinaryAvailable else {
            // Model or binary not available: return deterministic transcript immediately with zero delay
            return transcript
        }

        if let llamaServerURL = try? await DictationLlamaServerManager.shared.ensureRunning(idleRelease: settings.idleRelease) {
            let chatEndpoint = llamaServerURL.appendingPathComponent("v1/chat/completions")
            if let output = try? await sendChatRequest(
                model: "s1-mini",
                systemPrompt: effectiveSystemPrompt,
                userMessage: userMessage,
                transcriptWordCount: transcriptWordCount,
                endpointURL: chatEndpoint
            ) {
                return output
            } else if let retryURL = try? await DictationLlamaServerManager.shared.ensureRunning(idleRelease: settings.idleRelease, forceRestart: true) {
                let retryEndpoint = retryURL.appendingPathComponent("v1/chat/completions")
                if let output = try? await sendChatRequest(
                    model: "s1-mini",
                    systemPrompt: effectiveSystemPrompt,
                    userMessage: userMessage,
                    transcriptWordCount: transcriptWordCount,
                    endpointURL: retryEndpoint
                ) {
                    return output
                }
            }
        }

        return transcript
    }

    /// Transforms or rewrites text according to a voice command instruction (Command Mode & Transforms).
    func transform(
        text: String,
        instruction: String,
        settings: DictationS1Settings,
        endpointURL: URL? = nil,
        model: String = "s1-mini"
    ) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        let systemPrompt = "You are a precise voice-directed text editing assistant. Apply the user's spoken instruction to the provided text. Output ONLY the resulting edited text directly. Do not include introductory notes, conversational commentary, conversational filler, quotes, or markdown code block fences unless specifically requested by the instruction."
        let userMessage = "Instruction: \(instruction)\n\nOriginal Text:\n\(text)"
        let wordCount = text.split(separator: " ").count + instruction.split(separator: " ").count

        if let customEndpoint = endpointURL {
            let chatEndpoint = customEndpoint.path.hasSuffix("/v1/chat/completions") ? customEndpoint : customEndpoint.appendingPathComponent("v1/chat/completions")
            if let output = try? await sendChatRequest(
                model: model,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                transcriptWordCount: wordCount,
                endpointURL: chatEndpoint
            ) {
                return output
            }
            return text
        }

        guard DictationLlamaServerManager.isModelAvailable && DictationLlamaServerManager.isBinaryAvailable else {
            return text
        }

        if let llamaServerURL = try? await DictationLlamaServerManager.shared.ensureRunning(idleRelease: settings.idleRelease) {
            let chatEndpoint = llamaServerURL.appendingPathComponent("v1/chat/completions")
            if let output = try? await sendChatRequest(
                model: "s1-mini",
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                transcriptWordCount: wordCount,
                endpointURL: chatEndpoint
            ) {
                return output
            }
        }

        return text
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

    private func sendChatRequest(
        model: String,
        systemPrompt: String,
        userMessage: String,
        transcriptWordCount: Int,
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

        let cap = max(24, min(4096, transcriptWordCount * 2 + 32))
        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userMessage)
            ],
            temperature: 0.0,
            stream: false,
            max_tokens: cap
        )

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.timeoutInterval = max(10.0, Double(transcriptWordCount) * 0.05 + 10.0)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await Self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let output = decoded.choices.first?.message.content, !output.isEmpty else {
            return nil
        }
        return Self.cleanOutput(output)
    }
}
