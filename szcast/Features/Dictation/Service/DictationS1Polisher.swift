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

        do {
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 4.0
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return transcript
            }

            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            if let output = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output
            }
        } catch {
            Self.logger.notice("S1 polish unavailable or timed out; using deterministic text: \(error.localizedDescription)")
        }

        return transcript
    }
}
