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

    /// Builds a `wss://api.deepgram.com/v1/listen` URL for live linear16 PCM streaming.
    static func streamingURL(
        model: String = "nova-3",
        language: String? = nil,
        keyterms: [String] = []
    ) -> URL? {
        guard var components = URLComponents(string: "wss://api.deepgram.com/v1/listen") else {
            return nil
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "interim_results", value: "false")
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
        return components.url
    }
}

/// Persistent Deepgram WebSocket client streaming live PCM16 frames during capture.
actor DeepgramStreamingSession {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DeepgramStream")
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var transcripts: [String] = []
    private var failed = false

    func start(
        apiKey: String,
        model: String,
        language: String?,
        keyterms: [String]
    ) {
        cancel()
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty,
              let url = DeepgramAudioService.streamingURL(model: model, language: language, keyterms: keyterms)
        else {
            failed = true
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Token \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let ws = URLSession.shared.webSocketTask(with: request)
        self.task = ws
        self.failed = false
        self.transcripts = []
        ws.resume()

        self.receiveTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    let message = try await ws.receive()
                    switch message {
                    case .string(let text):
                        await self.handleMessageText(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleMessageText(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    await self.markFailed()
                    break
                }
            }
        }
    }

    func sendPCM(_ samples: [Float]) {
        guard !failed, let task, !samples.isEmpty else { return }
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var pcm16 = Int16(clamped * 32_767.0).littleEndian
            withUnsafeBytes(of: &pcm16) { data.append(contentsOf: $0) }
        }
        task.send(.data(data)) { [weak self] error in
            if error != nil {
                Task { await self?.markFailed() }
            }
        }
    }

    func finish() async -> String? {
        guard !failed, let ws = task else {
            cancel()
            return nil
        }
        do {
            try await ws.send(.string("{\"type\":\"CloseStream\"}"))
        } catch {
            cancel()
            return nil
        }

        let reader = receiveTask
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await reader?.value
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(1_500))
            }
            _ = await group.next()
            group.cancelAll()
        }

        let out = transcripts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        cancel()
        return out.isEmpty ? nil : out
    }

    func cancel() {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func markFailed() {
        failed = true
    }

    private func handleMessageText(_ json: String) {
        struct StreamPayload: Decodable {
            struct Channel: Decodable {
                struct Alternative: Decodable { let transcript: String? }
                let alternatives: [Alternative]?
            }
            let is_final: Bool?
            let channel: Channel?
        }
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(StreamPayload.self, from: data),
              payload.is_final == true,
              let piece = payload.channel?.alternatives?.first?.transcript
        else { return }
        let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            transcripts.append(trimmed)
        }
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
