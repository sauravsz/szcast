import Foundation
import OSLog

actor DeepgramAudioService {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DeepgramAudio")
    private static let endpoint = "https://api.deepgram.com/v1/listen"

    enum DeepgramAudioError: LocalizedError {
        case missingAPIKey
        case emptyAudio
        case invalidURL
        case invalidResponse(Int, String)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return String(localized: "Deepgram API key not set in Dictation Model Library.")
            case .emptyAudio:
                return String(localized: "No speech audio recorded.")
            case .invalidURL:
                return String(localized: "Failed to build Deepgram transcription URL.")
            case .invalidResponse(let code, let msg):
                return String(localized: "Deepgram API error (\(code)): \(msg)")
            case .decodingFailed:
                return String(localized: "Failed to decode Deepgram transcription response.")
            }
        }
    }

    /// Transcribes 16kHz mono Float samples via Deepgram's `/v1/listen` REST API.
    func transcribe(
        samples: [Float],
        apiKey: String,
        model: String = "nova-3",
        language: String? = nil,
        keyterms: [String] = []
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw DeepgramAudioError.missingAPIKey
        }
        guard !samples.isEmpty else {
            throw DeepgramAudioError.emptyAudio
        }

        guard var components = URLComponents(string: Self.endpoint) else {
            throw DeepgramAudioError.invalidURL
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true")
        ]
        if let langCode = DictationLanguage.isoCode(for: language) {
            items.append(URLQueryItem(name: "language", value: langCode))
        } else {
            items.append(URLQueryItem(name: "detect_language", value: "true"))
        }

        let termParam = model.hasPrefix("nova-3") ? "keyterm" : "keywords"
        for term in keyterms.prefix(25) {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                items.append(URLQueryItem(name: termParam, value: trimmed))
            }
        }
        components.queryItems = items

        guard let url = components.url else {
            throw DeepgramAudioError.invalidURL
        }

        let wavData = DictationWAVEncoder.encodePCM16(samples: samples, sampleRate: 16000)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        request.httpBody = wavData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepgramAudioError.decodingFailed
        }

        guard (200...299).contains(http.statusCode) else {
            let message = Self.parseErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            Self.logger.error("Deepgram transcription failed (\(http.statusCode)): \(message)")
            throw DeepgramAudioError.invalidResponse(http.statusCode, message)
        }

        struct ListenResponse: Decodable {
            struct Results: Decodable {
                struct Channel: Decodable {
                    struct Alternative: Decodable {
                        let transcript: String?
                    }
                    let alternatives: [Alternative]?
                }
                let channels: [Channel]?
            }
            let results: Results?
        }

        guard let decoded = try? JSONDecoder().decode(ListenResponse.self, from: data) else {
            throw DeepgramAudioError.decodingFailed
        }

        let transcript = decoded.results?.channels?.first?.alternatives?.first?.transcript ?? ""
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        struct ErrorPayload: Decodable {
            let err_msg: String?
            let message: String?
            let error: String?
        }
        if let parsed = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            return parsed.err_msg ?? parsed.message ?? parsed.error
        }
        return String(data: data, encoding: .utf8)
    }
}

/// Shared cloud STT dispatcher across live dictation, media ingest, and meeting notes.
enum DictationCloudSpeechService {
    static func hasAPIKey(
        for provider: DictationCloudSpeechProvider,
        groqAPIKey: String,
        deepgramAPIKey: String
    ) -> Bool {
        switch provider {
        case .groq:
            return !groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .deepgram:
            return !deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func missingKeyPrompt(for provider: DictationCloudSpeechProvider) -> String {
        switch provider {
        case .groq:
            return String(localized: "Set your Groq API key in Model Library first")
        case .deepgram:
            return String(localized: "Set your Deepgram API key in Model Library first")
        }
    }

    static func transcribe(
        provider: DictationCloudSpeechProvider,
        samples: [Float],
        groqAudio: GroqAudioService,
        deepgramAudio: DeepgramAudioService,
        groqAPIKey: String,
        deepgramAPIKey: String,
        groqModel: String,
        deepgramModel: String,
        language: String?,
        keyterms: [String] = [],
        groqPrompt: String? = nil
    ) async throws -> (text: String, modelID: String) {
        switch provider {
        case .groq:
            let text = try await groqAudio.transcribe(
                samples: samples,
                apiKey: groqAPIKey,
                model: groqModel,
                language: language,
                prompt: groqPrompt
            )
            return (text, groqModel)
        case .deepgram:
            let text = try await deepgramAudio.transcribe(
                samples: samples,
                apiKey: deepgramAPIKey,
                model: deepgramModel,
                language: language,
                keyterms: keyterms
            )
            return (text, deepgramModel)
        }
    }
}
