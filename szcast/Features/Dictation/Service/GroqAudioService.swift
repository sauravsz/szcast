import AVFoundation
import Foundation
import OSLog

actor GroqAudioService {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "GroqAudio")
    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!

    enum GroqAudioError: LocalizedError {
        case missingAPIKey
        case emptyAudio
        case invalidResponse(Int, String)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return String(localized: "Groq API key not set in Dictation Settings.")
            case .emptyAudio:
                return String(localized: "No speech audio recorded.")
            case .invalidResponse(let code, let msg):
                return String(localized: "Groq API error (\(code)): \(msg)")
            case .decodingFailed:
                return String(localized: "Failed to decode Groq transcription response.")
            }
        }
    }

    /// Transcribe 16kHz mono Float samples via Groq's high-speed Whisper endpoint.
    func transcribe(
        samples: [Float],
        apiKey: String,
        model: String = "whisper-large-v3-turbo",
        language: String? = nil,
        prompt: String? = nil
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw GroqAudioError.missingAPIKey
        }
        guard !samples.isEmpty else {
            throw GroqAudioError.emptyAudio
        }

        let compressedM4A = samples.count >= 8_000
            ? DictationWAVEncoder.encodeCompressedM4A(samples: samples, sampleRate: 16_000)
            : nil
        let uploadData = compressedM4A ?? DictationWAVEncoder.encodePCM16(samples: samples, sampleRate: 16_000)
        let uploadFilename = compressedM4A != nil ? "dictation.m4a" : "dictation.wav"
        let uploadContentType = compressedM4A != nil ? "audio/mp4" : "audio/wav"
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0

        var body = Data()

        // 1. Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // 2. Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)

        // 3. Language (optional; omitted in auto-detect so multilingual code-switching works naturally)
        if let langCode = DictationLanguage.isoCode(for: language) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(langCode)\r\n".data(using: .utf8)!)
        }

        // 4. Contextual vocabulary & surrounding snippet prompt (bounded to stay within Whisper limits)
        if let trimmedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedPrompt.isEmpty {
            let safePrompt = trimmedPrompt.count > 700 ? String(trimmedPrompt.suffix(700)) : trimmedPrompt
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(safePrompt)\r\n".data(using: .utf8)!)
        }

        // 4. Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(uploadFilename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(uploadContentType)\r\n\r\n".data(using: .utf8)!)
        body.append(uploadData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GroqAudioError.decodingFailed
        }

        guard (200...299).contains(http.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            Self.logger.error("Groq transcription failed (\(http.statusCode)): \(errorMessage)")
            throw GroqAudioError.invalidResponse(http.statusCode, errorMessage)
        }

        struct TranscriptionResponse: Decodable {
            let text: String
        }

        guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw GroqAudioError.decodingFailed
        }

        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DictationWAVEncoder {
    /// Generates compact 32 kbps mono AAC `.m4a` payload (~8x smaller than PCM16 WAV) for cloud upload.
    static func encodeCompressedM4A(samples: [Float], sampleRate: Double = 16_000) -> Data? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0]
        else { return nil }

        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                channel.update(from: base, count: samples.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("szcast-groq-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ]
        do {
            let file = try AVAudioFile(
                forWriting: tempURL,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try file.write(from: buffer)
            return try Data(contentsOf: tempURL)
        } catch {
            return nil
        }
    }

    /// Generate standard 16-bit PCM RIFF WAV data from mono Float samples.
    static func encodePCM16(samples: [Float], sampleRate: Int = 16000) -> Data {
        let numSamples = samples.count
        let byteRate = sampleRate * 2
        let subChunk2Size = numSamples * 2
        let chunkSize = 36 + subChunk2Size

        var data = Data(capacity: 44 + subChunk2Size)
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(chunkSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)

        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(UInt16(2).littleEndianData)
        data.append(UInt16(16).littleEndianData)

        data.append("data".data(using: .ascii)!)
        data.append(UInt32(subChunk2Size).littleEndianData)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * 32767.0)
            data.append(intSample.littleEndianData)
        }

        return data
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
