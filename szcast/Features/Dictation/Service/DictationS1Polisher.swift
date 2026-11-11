import Foundation
import OSLog

actor DictationS1Polisher {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationS1Polish")

    func polish(
        _ transcript: String,
        settings: DictationS1Settings,
        endpointURL: URL = URL(string: "http://localhost:11434/v1/chat/completions")!,
        model: String = "superwhisper/s1-mini-gguf"
    ) async -> String {
        guard settings.enabled, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return transcript
        }

        let userMessage = "\(settings.controlLine)\n\(transcript)"

        do {
            if let output = try await sendRequest(model: model, userMessage: userMessage, endpointURL: endpointURL) {
                return output
            }
            // Fallback: If default model is unavailable, check Ollama for available models
            if let tagsURL = URL(string: "http://localhost:11434/api/tags"),
               let fallbackModel = await resolveFallbackModel(tagsURL: tagsURL, excluding: model) {
                if let output = try await sendRequest(model: fallbackModel, userMessage: userMessage, endpointURL: endpointURL) {
                    return output
                }
            }
        } catch {
            Self.logger.notice("S1 polish unavailable or timed out; using deterministic text: \(error.localizedDescription)")
        }

        return transcript
    }

    private func sendRequest(model: String, userMessage: String, endpointURL: URL) async throws -> String? {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct RequestBody: Encodable {
            let model: String
            let messages: [Message]
            let temperature: Double
            let stream: Bool
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

        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: DictationS1Settings.systemPrompt),
                Message(role: "user", content: userMessage)
            ],
            temperature: 0.1,
            stream: false
        )

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4.0
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        if let output = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
            return output
        }
        return nil
    }

    private func resolveFallbackModel(tagsURL: URL, excluding: String) async -> String? {
        struct TagsResponse: Decodable {
            struct TagModel: Decodable {
                let name: String
            }
            let models: [TagModel]
        }
        var request = URLRequest(url: tagsURL)
        request.timeoutInterval = 1.5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            return nil
        }
        let preferred = ["s1-mini", "ministral-3:3b", "qwen3.5:2b", "phi4-mini:3.8b", "llama3.2:3b"]
        for pref in preferred {
            if let match = decoded.models.first(where: { $0.name.localizedCaseInsensitiveContains(pref) }), match.name != excluding {
                return match.name
            }
        }
        return decoded.models.first(where: { $0.name != excluding })?.name
    }
}
