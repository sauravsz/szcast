import Accelerate
import CoreML
import Foundation

/// Runs offline Indic + English ASR using spashii/SraVaani-1.0-CoreML (FastConformer-TDT).
final class SraVaaniRecognizer {
    private let encoder: MLModel
    private let decoder: MLModel
    private let vocabulary: [Int: String]
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let filters: [Float]

    private static let sampleRate = 16_000
    private static let nFFT = 512
    private static let winLength = 400
    private static let hopLength = 160
    private static let melBands = 128
    private static let maxFrames = 3000
    private static let hiddenSize = 640
    private static let vocabSize = 5001
    private static let blankID = 5000
    private static let durations = [0, 1, 2, 3, 4]
    private static let maxWindowSamples = maxFrames * hopLength

    init(directory: URL) throws {
        let encoderConfig = MLModelConfiguration()
        encoderConfig.computeUnits = .cpuAndNeuralEngine
        encoderConfig.functionName = "window30"
        encoder = try MLModel(
            contentsOf: directory.appendingPathComponent("SraVaaniEncoder.mlmodelc"),
            configuration: encoderConfig
        )

        let decoderConfig = MLModelConfiguration()
        decoderConfig.computeUnits = .cpuOnly
        decoder = try MLModel(
            contentsOf: directory.appendingPathComponent("SraVaaniDecoder.mlmodelc"),
            configuration: decoderConfig
        )

        let tokenizerData = try Data(contentsOf: directory.appendingPathComponent("tokenizer.model"))
        vocabulary = try Self.parseSentencePieceVocabulary(from: tokenizerData)

        guard let fft = vDSP.FFT(log2n: 9, radix: .radix2, ofType: DSPSplitComplex.self) else {
            throw DictationInferenceError.incompatibleModel
        }
        self.fft = fft
        window = (0..<Self.winLength).map { 0.5 * (1.0 - cos(2.0 * .pi * Float($0) / Float(Self.winLength))) }
        filters = Self.makeSlaneyMelFilters()
    }

    func transcribeTimed(_ samples: [Float], language: String?) throws -> TimedTranscript {
        guard !samples.isEmpty, samples.count <= DictationWire.maximumSamples else {
            throw DictationInferenceError.invalidAudio
        }

        var allPieces = [(piece: String, start: TimeInterval, end: TimeInterval)]()
        var chunkTexts = [String]()
        for range in DictationAudioChunks.ranges(in: samples, maximum: Self.maxWindowSamples) {
            let offsetSeconds = Double(range.lowerBound) / Double(Self.sampleRate)
            let chunkPieces = try autoreleasepool { try decode(samples[range], offsetSeconds: offsetSeconds) }
            allPieces.append(contentsOf: chunkPieces)
            let chunkText = chunkPieces.map(\.piece).joined()
                .replacingOccurrences(of: "▁", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunkText.isEmpty { chunkTexts.append(chunkText) }
        }
        let text = chunkTexts.joined(separator: " ")
        let words = TranscriptSegmentBuilder.mergeSubwordPieces(allPieces)
        let segments = TranscriptSegmentBuilder.build(words: words, fallbackText: text)
        return TimedTranscript(text: text, words: words, segments: segments)
    }

    private func decode(
        _ samples: ArraySlice<Float>,
        offsetSeconds: TimeInterval
    ) throws -> [(piece: String, start: TimeInterval, end: TimeInterval)] {
        let (melValues, frameCount) = logMelFeatures(samples)
        let melTensor = try DictationTensor.zeros([1, Self.melBands, Self.maxFrames], type: .float32)
        melTensor.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            _ = buffer.update(from: melValues)
        }
        let encoded = try DictationTensor.predict(
            encoder,
            ["mel": melTensor, "length": DictationTensor.integer(frameCount)]
        )
        let features = try DictationTensor.array("encoded", from: encoded)
        let encodedLengths = try DictationTensor.array("encoded_length", from: encoded)
        guard encodedLengths.count > 0 else { throw DictationInferenceError.incompatibleModel }
        let length = encodedLengths[0].intValue
        guard features.shape.count == 3,
              features.shape[2].intValue == Self.hiddenSize,
              length > 0,
              length <= features.shape[1].intValue
        else {
            throw DictationInferenceError.incompatibleModel
        }

        let vectors = MLShapedArray<Float>(converting: features)
        var hidden = try DictationTensor.zeros([1, 1, Self.hiddenSize], type: .float32)
        var cell = try DictationTensor.zeros([1, 1, Self.hiddenSize], type: .float32)
        let frame = try DictationTensor.zeros([1, 1, Self.hiddenSize], type: .float32)
        var lastToken = Self.blankID
        var time = 0
        var emissions = 0
        let frameSeconds = 0.08
        var pieces = [(piece: String, start: TimeInterval, end: TimeInterval)]()

        while time < length {
            vectors.withUnsafeShapedBufferPointer { source, _, strides in
                frame.withUnsafeMutableBufferPointer(ofType: Float.self) { target, _ in
                    let base = time * strides[1]
                    for channel in 0..<Self.hiddenSize {
                        target[channel] = source[base + channel * strides[2]]
                    }
                }
            }

            let stepOut = try DictationTensor.predict(
                decoder,
                [
                    "enc_frame": frame,
                    "token": DictationTensor.integer(lastToken, shape: [1, 1]),
                    "h_in": hidden,
                    "c_in": cell
                ]
            )
            let logits = try DictationTensor.array("logits", from: stepOut)
            guard logits.count >= Self.vocabSize + Self.durations.count else {
                throw DictationInferenceError.incompatibleModel
            }

            var bestToken = Self.blankID
            var bestTokenScore: Float = -.infinity
            for idx in 0..<Self.vocabSize {
                let score = logits[idx].floatValue
                if score > bestTokenScore { bestTokenScore = score; bestToken = idx }
            }

            var bestDurationIndex = 0
            var bestDurationScore: Float = -.infinity
            for idx in 0..<Self.durations.count {
                let score = logits[Self.vocabSize + idx].floatValue
                if score > bestDurationScore { bestDurationScore = score; bestDurationIndex = idx }
            }
            let duration = Self.durations[bestDurationIndex]

            if bestToken != Self.blankID {
                if let piece = vocabulary[bestToken], !piece.hasPrefix("<"), !piece.isEmpty {
                    let start = offsetSeconds + Double(time) * frameSeconds
                    let end = offsetSeconds + Double(time + max(1, duration)) * frameSeconds
                    pieces.append((piece, start, end))
                }
                hidden = try DictationTensor.array("h_out", from: stepOut)
                cell = try DictationTensor.array("c_out", from: stepOut)
                lastToken = bestToken
                emissions += 1
            }

            let step = (bestToken == Self.blankID || emissions >= 10) ? max(1, duration) : duration
            if step > 0 { time += step; emissions = 0 }
        }
        return pieces
    }

    /// Computes `[1, 128, 3000]` Slaney log-mel features normalized per frequency band.
    func logMelFeatures(_ samples: ArraySlice<Float>) -> (values: [Float], frames: Int) {
        let count = samples.count
        let frameCount: Int
        if count < Self.nFFT {
            frameCount = 1
        } else {
            frameCount = min(Self.maxFrames, (count - Self.nFFT) / Self.hopLength + 1)
        }
        let bins = Self.nFFT / 2 + 1
        let padOffset = (Self.nFFT - Self.winLength) / 2
        var powers = [Float](repeating: 0, count: bins * frameCount)

        var frameBuf = [Float](repeating: 0, count: Self.nFFT)
        var realBuf = [Float](repeating: 0, count: Self.nFFT / 2)
        var imagBuf = [Float](repeating: 0, count: Self.nFFT / 2)

        for t in 0..<frameCount {
            for i in 0..<Self.nFFT { frameBuf[i] = 0 }
            let start = t * Self.hopLength
            for i in 0..<Self.winLength {
                let sampleIndex = start + padOffset + i
                if sampleIndex < count {
                    frameBuf[padOffset + i] = samples[samples.startIndex + sampleIndex] * window[i]
                }
            }
            frameBuf.withUnsafeBufferPointer { src in
                realBuf.withUnsafeMutableBufferPointer { rPtr in
                    imagBuf.withUnsafeMutableBufferPointer { iPtr in
                        var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                        src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.nFFT / 2) { cPtr in
                            vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(Self.nFFT / 2))
                        }
                        fft.forward(input: split, output: &split)
                        // vDSP_fft_zrip scales forward output by 2.0; DC sits in real[0], Nyquist in imag[0].
                        powers[0 * frameCount + t] = 0.25 * rPtr[0] * rPtr[0]
                        powers[(bins - 1) * frameCount + t] = 0.25 * iPtr[0] * iPtr[0]
                        for k in 1..<(Self.nFFT / 2) {
                            powers[k * frameCount + t] = 0.25 * (rPtr[k] * rPtr[k] + iPtr[k] * iPtr[k])
                        }
                    }
                }
            }
        }

        var melCompact = [Float](repeating: 0, count: Self.melBands * frameCount)
        vDSP_mmul(filters, 1, powers, 1, &melCompact, 1, vDSP_Length(Self.melBands), vDSP_Length(frameCount), vDSP_Length(bins))

        let logFloor: Float = 5.960464477539063e-08 // 2^-24
        var normalized = [Float](repeating: 0, count: Self.melBands * Self.maxFrames)
        for band in 0..<Self.melBands {
            let compactOffset = band * frameCount
            let outOffset = band * Self.maxFrames
            var sum: Float = 0
            for t in 0..<frameCount {
                let v = log(max(0, melCompact[compactOffset + t]) + logFloor)
                melCompact[compactOffset + t] = v
                sum += v
            }
            let mean = sum / Float(frameCount)
            var varSum: Float = 0
            for t in 0..<frameCount {
                let d = melCompact[compactOffset + t] - mean
                varSum += d * d
            }
            let invStd = 1.0 / (sqrt(varSum / Float(frameCount)) + 1e-5)
            for t in 0..<frameCount {
                normalized[outOffset + t] = (melCompact[compactOffset + t] - mean) * invStd
            }
        }
        return (normalized, frameCount)
    }

    /// Parses SentencePiece `.model` protobuf (`ModelProto.pieces[].piece`) without external C dependencies.
    static func parseSentencePieceVocabulary(from data: Data) throws -> [Int: String] {
        let bytes = [UInt8](data)
        let count = bytes.count
        var index = 0
        var pieces = [Int: String]()
        var pieceIndex = 0

        func readVarint(_ cursor: inout Int) throws -> UInt64 {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while cursor < count {
                let byte = bytes[cursor]
                cursor += 1
                value |= UInt64(byte & 0x7F) << shift
                if (byte & 0x80) == 0 { return value }
                shift += 7
                if shift >= 64 { throw DictationInferenceError.incompatibleModel }
            }
            throw DictationInferenceError.incompatibleModel
        }

        while index < count {
            let tag = try readVarint(&index)
            let fieldNumber = tag >> 3
            let wireType = tag & 7
            switch wireType {
            case 2:
                let length = Int(try readVarint(&index))
                guard length >= 0, index + length <= count else { throw DictationInferenceError.incompatibleModel }
                let end = index + length
                if fieldNumber == 1 {
                    var sub = index
                    var tokenText = ""
                    while sub < end {
                        let subTag = try readVarint(&sub)
                        let subField = subTag >> 3
                        let subWire = subTag & 7
                        switch subWire {
                        case 2:
                            let strLen = Int(try readVarint(&sub))
                            guard strLen >= 0, sub + strLen <= end else { throw DictationInferenceError.incompatibleModel }
                            if subField == 1 {
                                tokenText = String(bytes: bytes[sub..<(sub + strLen)], encoding: .utf8) ?? ""
                            }
                            sub += strLen
                        case 0: _ = try readVarint(&sub)
                        case 1: sub += 8
                        case 5: sub += 4
                        default: throw DictationInferenceError.incompatibleModel
                        }
                    }
                    pieces[pieceIndex] = tokenText
                    pieceIndex += 1
                }
                index = end
            case 0: _ = try readVarint(&index)
            case 1: index += 8
            case 5: index += 4
            default: throw DictationInferenceError.incompatibleModel
            }
        }
        guard !pieces.isEmpty else { throw DictationInferenceError.incompatibleModel }
        return pieces
    }

    private static func makeSlaneyMelFilters() -> [Float] {
        func mel(_ hz: Float) -> Float {
            hz < 1000 ? hz / (200.0 / 3.0) : 15.0 + log(hz / 1000.0) / (log(6.4) / 27.0)
        }
        func hz(_ m: Float) -> Float {
            m < 15.0 ? m * (200.0 / 3.0) : 1000.0 * exp((m - 15.0) * (log(6.4) / 27.0))
        }
        let bins = nFFT / 2 + 1
        let binStep = Float(sampleRate) / Float(nFFT)
        let edges = (0..<(melBands + 2)).map { hz(Float($0) * mel(Float(sampleRate) / 2.0) / Float(melBands + 1)) }
        return (0..<melBands).flatMap { band in
            (0..<bins).map { bin -> Float in
                let freq = Float(bin) * binStep
                let rising = (freq - edges[band]) / (edges[band + 1] - edges[band])
                let falling = (edges[band + 2] - freq) / (edges[band + 2] - edges[band + 1])
                return max(0, min(rising, falling)) * 2.0 / (edges[band + 2] - edges[band])
            }
        }
    }
}
