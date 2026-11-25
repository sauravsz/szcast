import CoreML
import Foundation

final class NemotronRecognizer {
    private static let chunkAudioSamples = 480_000
    private static let chunkMelFrames = 112
    private static let preEncodeCacheFrames = 9
    private static let totalMelFrames = 121
    private static let blankToken = 1_024
    private static let frameSeconds = 0.08

    private let preprocessor: MLModel
    private let encoder: MLModel
    private let decoder: MLModel
    private let joint: MLModel
    private let vocabulary: [Int: String]

    init(directory: URL) throws {
        let base = directory.appendingPathComponent("nemotron_coreml_1120ms")
        preprocessor = try DictationTensor.load("preprocessor", at: base, units: .cpuOnly)
        encoder = try DictationTensor.load(
            "encoder/encoder_int8", at: base, units: .cpuAndNeuralEngine)
        decoder = try DictationTensor.load("decoder", at: base, units: .cpuOnly)
        joint = try DictationTensor.load("joint", at: base, units: .cpuOnly)

        let tokData = try Data(contentsOf: base.appendingPathComponent("tokenizer.json"))
        let raw = try JSONDecoder().decode([String: String].self, from: tokData)
        var table = [Int: String]()
        for (k, v) in raw {
            if let id = Int(k) { table[id] = v }
        }
        vocabulary = table
    }

    func transcribe(_ samples: [Float]) throws -> String {
        try transcribeTimed(samples).text
    }

    func transcribeTimed(_ samples: [Float]) throws -> TimedTranscript {
        guard !samples.isEmpty, samples.count <= DictationWire.maximumSamples else {
            throw DictationInferenceError.invalidAudio
        }

        var cacheChannel = try DictationTensor.zeros([1, 24, 70, 1024])
        var cacheTime = try DictationTensor.zeros([1, 24, 1024, 8])
        var cacheLen = try DictationTensor.integer(0)
        var hState = try DictationTensor.zeros([2, 1, 640])
        var cState = try DictationTensor.zeros([2, 1, 640])
        var lastToken = Self.blankToken

        func advanceDecoder(_ token: Int) throws -> MLMultiArray {
            let out = try DictationTensor.predict(
                decoder,
                [
                    "token": DictationTensor.integer(token, shape: [1, 1]),
                    "token_length": DictationTensor.integer(1),
                    "h_in": hState,
                    "c_in": cState
                ]
            )
            hState = try DictationTensor.array("h_out", from: out)
            cState = try DictationTensor.array("c_out", from: out)
            return try DictationTensor.array("decoder_out", from: out)
        }

        var decoderOut = try advanceDecoder(lastToken)
        var carryMel = [Float](repeating: 0, count: 128 * Self.preEncodeCacheFrames)
        var globalSeconds = 0.0
        var pieces = [(piece: String, start: TimeInterval, end: TimeInterval)]()
        var chunkTexts = [String]()

        let encoderFrame = try DictationTensor.zeros([1, 1024, 1])

        for range in DictationAudioChunks.ranges(in: samples, maximum: Self.chunkAudioSamples) {
            try autoreleasepool {
                let slice = samples[range]
                let audio = try DictationTensor.zeros([1, slice.count])
                audio.withUnsafeMutableBufferPointer(ofType: Float.self) { dst, _ in
                    for (idx, val) in slice.enumerated() { dst[idx] = val }
                }
                let prep = try DictationTensor.predict(
                    preprocessor,
                    [
                        "audio": audio,
                        "audio_length": DictationTensor.integer(slice.count)
                    ]
                )
                let melArray = try DictationTensor.array("mel", from: prep)
                let melLength = try DictationTensor.array("mel_length", from: prep)[0].intValue
                let availableFrames = min(melLength, melArray.shape[2].intValue)
                let melValues = try DictationTensor.floatValues(from: melArray)
                let totalBinsStride = melArray.shape[2].intValue

                var frameStart = 0
                while frameStart < availableFrames {
                    let chunkCount = min(Self.chunkMelFrames, availableFrames - frameStart)
                    let melInput = try DictationTensor.zeros([1, 128, Self.totalMelFrames])
                    let validTotal = Self.preEncodeCacheFrames + chunkCount
                    melInput.withUnsafeMutableBufferPointer(ofType: Float.self) { dst, _ in
                        dst.initialize(repeating: 0)
                        for band in 0..<128 {
                            let dstRow = band * Self.totalMelFrames
                            let carryRow = band * Self.preEncodeCacheFrames
                            for p in 0..<Self.preEncodeCacheFrames {
                                dst[dstRow + p] = carryMel[carryRow + p]
                            }
                            let srcRow = band * totalBinsStride
                            for f in 0..<chunkCount {
                                dst[dstRow + Self.preEncodeCacheFrames + f] = melValues[srcRow + frameStart + f]
                            }
                        }
                    }

                    // Save last 9 valid frames as pre-encode cache for next chunk.
                    for band in 0..<128 {
                        let dstRow = band * Self.preEncodeCacheFrames
                        let srcRow = band * Self.totalMelFrames
                        melInput.withUnsafeBufferPointer(ofType: Float.self) { src in
                            for p in 0..<Self.preEncodeCacheFrames {
                                let sourceFrame = max(0, validTotal - Self.preEncodeCacheFrames + p)
                                carryMel[dstRow + p] = src[srcRow + sourceFrame]
                            }
                        }
                    }

                    let encOut = try DictationTensor.predict(
                        encoder,
                        [
                            "cache_channel": cacheChannel,
                            "cache_len": cacheLen,
                            "cache_time": cacheTime,
                            "mel": melInput,
                            "mel_length": DictationTensor.integer(validTotal)
                        ]
                    )
                    cacheChannel = try DictationTensor.array("cache_channel_out", from: encOut)
                    cacheTime = try DictationTensor.array("cache_time_out", from: encOut)
                    cacheLen = try DictationTensor.array("cache_len_out", from: encOut)
                    let encoded = try DictationTensor.array("encoded", from: encOut)
                    let encodedLen = min(
                        encoded.shape[2].intValue,
                        try DictationTensor.array("encoded_length", from: encOut)[0].intValue
                    )
                    let encodedShaped = MLShapedArray<Float>(converting: encoded)
                    let chunkBaseSeconds = globalSeconds + Double(frameStart) * 0.01

                    for t in 0..<encodedLen {
                        encodedShaped.withUnsafeShapedBufferPointer { src, _, strides in
                            encoderFrame.withUnsafeMutableBufferPointer(ofType: Float.self) { dst, _ in
                                for c in 0..<1024 {
                                    dst[c] = src[c * strides[1] + t * strides[2]]
                                }
                            }
                        }

                        var emitted = 0
                        while emitted < 10 {
                            let jOut = try DictationTensor.predict(
                                joint, ["decoder": decoderOut, "encoder": encoderFrame])
                            let logits = try DictationTensor.array("logits", from: jOut)
                            let values = try DictationTensor.floatValues(from: logits)
                            guard let token = values.indices.max(by: { values[$0] < values[$1] }) else {
                                break
                            }
                            if token == Self.blankToken { break }
                            if let piece = vocabulary[token], !piece.hasPrefix("<") {
                                let s = chunkBaseSeconds + Double(t) * Self.frameSeconds
                                pieces.append((piece, s, s + Self.frameSeconds))
                            }
                            lastToken = token
                            decoderOut = try advanceDecoder(token)
                            emitted += 1
                        }
                    }
                    frameStart += Self.chunkMelFrames
                }
                globalSeconds += Double(slice.count) / Double(DictationWire.sampleRate)
            }
        }

        let words = TranscriptSegmentBuilder.mergeSubwordPieces(pieces)
        let fullText = pieces.map(\.piece).joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullText.isEmpty { chunkTexts.append(fullText) }
        let final = chunkTexts.joined(separator: " ")
        let segments = TranscriptSegmentBuilder.build(words: words, fallbackText: final)
        return TimedTranscript(text: final, words: words, segments: segments)
    }
}
