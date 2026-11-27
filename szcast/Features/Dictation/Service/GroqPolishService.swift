import Foundation
import OSLog

actor GroqPolishService {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "GroqPolish")
    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    enum GroqPolishError: LocalizedError {
        case missingAPIKey
        case emptyTranscript
        case invalidResponse(Int, String)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return String(localized: "Groq API key not set in Dictation Settings.")
            case .emptyTranscript:
                return String(localized: "Transcript is empty.")
            case .invalidResponse(let code, let msg):
                return String(localized: "Groq API error (\(code)): \(msg)")
            case .decodingFailed:
                return String(localized: "Failed to decode Groq polish response.")
            }
        }
    }

    /// Clean, normalize, and format speech transcript using Groq's low-latency LLM endpoint (~120ms).
    func polish(
        _ transcript: String,
        apiKey: String,
        settings: DictationS1Settings,
        vocabularyTerms: [String] = [],
        model: String = "openai/gpt-oss-120b"
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw GroqPolishError.missingAPIKey
        }
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return transcript
        }

        let isS1 = DictationS1Polisher.isS1Mini(model)
        let userMessage = DictationS1Settings.normalizedUserMessage(
            controlLine: settings.controlLine,
            transcript: trimmedTranscript,
            vocabularyTerms: vocabularyTerms,
            isS1Mini: isS1
        )
        let transcriptWordCount = trimmedTranscript.split(separator: " ").count
        let cap = max(32, min(4096, transcriptWordCount * 2 + 32))

        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct RequestBody: Encodable {
            let model: String
            let messages: [Message]
            let temperature: Double
            let max_tokens: Int
            let stream: Bool
        }

        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: settings.effectiveSystemPrompt(for: trimmedTranscript, isS1Mini: isS1)),
                Message(role: "user", content: userMessage)
            ],
            temperature: 0.0,
            max_tokens: cap,
            stream: false
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20.0
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GroqPolishError.decodingFailed
        }

        guard (200...299).contains(http.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            Self.logger.error("Groq polish failed (\(http.statusCode)): \(errorMessage)")
            throw GroqPolishError.invalidResponse(http.statusCode, errorMessage)
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

        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data),
              let output = decoded.choices.first?.message.content,
              !output.isEmpty else {
            throw GroqPolishError.decodingFailed
        }

        return DictationS1Polisher.cleanOutput(output) ?? trimmedTranscript
    }

    /// Rewrites selected text according to voice command instructions via Groq.
    func transform(
        text: String,
        instruction: String,
        apiKey: String,
        model: String = "openai/gpt-oss-120b"
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GroqPolishError.missingAPIKey }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let systemPrompt = "You are a precise voice-directed text editing assistant. Apply the user's spoken instruction to the provided text. Output ONLY the resulting edited text directly. Do not include introductory notes, conversational commentary, conversational filler, quotes, or markdown code block fences unless specifically requested by the instruction."
        let userMessage = "Instruction: \(instruction)\n\nOriginal Text:\n\(trimmed)"
        let wordCount = trimmed.split(separator: " ").count + instruction.split(separator: " ").count
        let cap = max(64, min(4096, wordCount * 3 + 64))

        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct RequestBody: Encodable {
            let model: String
            let messages: [Message]
            let temperature: Double
            let max_tokens: Int
            let stream: Bool
        }

        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userMessage)
            ],
            temperature: 0.1,
            max_tokens: cap,
            stream: false
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20.0
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GroqPolishError.decodingFailed }
        guard (200...299).contains(http.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GroqPolishError.invalidResponse(http.statusCode, errorMessage)
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

        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data),
              let output = decoded.choices.first?.message.content,
              !output.isEmpty else {
            throw GroqPolishError.decodingFailed
        }

        return DictationS1Polisher.cleanOutput(output) ?? trimmed
    }
}
