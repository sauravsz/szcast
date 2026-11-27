import Accelerate
import CoreML
import Foundation

final class ParakeetRecognizer {
    private let preprocessor: MLModel
    private let encoder: MLModel
    private let decoder: MLModel
    private let joint: MLModel
    private let vocabulary: [Int: String]
    private let blank: Int
    private static let windowSamples = 240_000
    private static let tailPadSamples = 800 // 50ms zero context for final plosives

    // Pre-allocated reusable input tensors eliminate per-chunk and per-step allocations.
    private let audioBuffer: MLMultiArray
    private let audioLengthTensor: MLMultiArray
    private let frameBuffer: MLMultiArray
    private let targetTokenTensor: MLMultiArray
    private let targetLengthTensor: MLMultiArray
    private let preprocessorProvider: MLDictionaryFeatureProvider
    private var warmedUp = false

    private struct DecoderState {
        var hidden: MLMultiArray
        var cell: MLMultiArray
        var projection: MLMultiArray
    }

    init(directory: URL, model: DictationModel) throws {
        guard let configuration = model.parakeetConfiguration else {
            throw DictationInferenceError.incompatibleModel
        }
        preprocessor = try DictationTensor.load("Preprocessor", at: directory, units: .cpuOnly)
        encoder = try DictationTensor.load(
            "Encoder", at: directory,
            units: configuration.encoderUsesGPU ? .cpuAndGPU : .cpuAndNeuralEngine)
        decoder = try DictationTensor.load("Decoder", at: directory, units: .cpuAndNeuralEngine)
        joint = try DictationTensor.load(
            configuration.joint,
            at: directory, units: .cpuAndNeuralEngine)
        let pieces = try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: directory.appendingPathComponent("parakeet_vocab.json")))
        vocabulary = Dictionary(
            uniqueKeysWithValues: try pieces.map { key, value in
                guard let id = Int(key), String(id) == key else {
                    throw DictationInferenceError.incompatibleModel
                }
                return (id, value)
            })
        blank = configuration.blankToken

        audioBuffer = try DictationTensor.zeros([1, Self.windowSamples])
        audioLengthTensor = try DictationTensor.integer(0)
        frameBuffer = try DictationTensor.zeros([1, 1024, 1])
        targetTokenTensor = try DictationTensor.integer(blank, shape: [1, 1])
        targetLengthTensor = try DictationTensor.integer(1)
        preprocessorProvider = try MLDictionaryFeatureProvider(dictionary: [
            "audio_signal": MLFeatureValue(multiArray: audioBuffer),
            "audio_length": MLFeatureValue(multiArray: audioLengthTensor)
        ])
    }

    /// Triggers an initial tiny forward pass during background prewarming so ANE/Metal plans JIT early.
    func warmupIfNeeded() {
        guard !warmedUp else { return }
        warmedUp = true
        _ = try? autoreleasepool {
            try transcribeTimed([Float](repeating: 0, count: 4_000))
        }
    }

    func transcribe(_ samples: [Float]) throws -> String {
        try transcribeTimed(samples).text
    }

    func transcribeTimed(_ samples: [Float]) throws -> TimedTranscript {
        guard !samples.isEmpty, samples.count <= DictationWire.maximumSamples else {
            throw DictationInferenceError.invalidAudio
        }
        let ranges = DictationAudioChunks.ranges(in: samples, maximum: Self.windowSamples)
        let initHidden = try DictationTensor.zeros([2, 1, 640])
        let initCell = try DictationTensor.zeros([2, 1, 640])
        let initialStep = try advanceDecoder(token: blank, hidden: initHidden, cell: initCell)
        var state = DecoderState(
            hidden: initialStep.hidden,
            cell: initialStep.cell,
            projection: initialStep.projection
        )

        var allPieces = [(piece: String, start: TimeInterval, end: TimeInterval)]()
        var chunkTexts = [String]()
        for (idx, range) in ranges.enumerated() {
            let offsetSeconds = Double(range.lowerBound) / Double(DictationWire.sampleRate)
            let isLastChunk = idx == ranges.count - 1
            let chunkPieces = try autoreleasepool {
                try decode(
                    samples[range],
                    offsetSeconds: offsetSeconds,
                    padTail: isLastChunk,
                    state: &state
                )
            }
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

    private func advanceDecoder(
        token: Int,
        hidden: MLMultiArray,
        cell: MLMultiArray
    ) throws -> (hidden: MLMultiArray, cell: MLMultiArray, projection: MLMultiArray) {
        DictationTensor.setInteger(token, in: targetTokenTensor)
        let prediction = try DictationTensor.predict(
            decoder,
            [
                "targets": targetTokenTensor,
                "target_length": targetLengthTensor,
                "h_in": hidden,
                "c_in": cell
            ]
        )
        let nextHidden = try DictationTensor.array("h_out", from: prediction)
        let nextCell = try DictationTensor.array("c_out", from: prediction)
        let nextProjection = try DictationTensor.array("decoder", from: prediction)
        return (nextHidden, nextCell, nextProjection)
    }

    private func decode(
        _ samples: ArraySlice<Float>,
        offsetSeconds: TimeInterval,
        padTail: Bool,
        state: inout DecoderState
    ) throws -> [(piece: String, start: TimeInterval, end: TimeInterval)] {
        let frameSeconds = 0.08
        let paddedCount = padTail
            ? min(Self.windowSamples, samples.count + Self.tailPadSamples)
            : samples.count

        audioBuffer.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            guard let base = buffer.baseAddress else { return }
            samples.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress else { return }
                base.update(from: srcBase, count: samples.count)
            }
            if samples.count < buffer.count {
                (base + samples.count).initialize(repeating: 0, count: buffer.count - samples.count)
            }
        }
        DictationTensor.setInteger(paddedCount, in: audioLengthTensor)

        let mel = try DictationTensor.predict(preprocessor, preprocessorProvider)
        let encoded = try DictationTensor.predict(
            encoder,
            [
                "mel": DictationTensor.array("mel", from: mel),
                "mel_length": DictationTensor.array("mel_length", from: mel)
            ]
        )
        let features = try DictationTensor.array("encoder", from: encoded)
        let encoderLengths = try DictationTensor.array("encoder_length", from: encoded)
        guard encoderLengths.count > 0 else { throw DictationInferenceError.incompatibleModel }
        let length = encoderLengths[0].intValue
        guard features.shape.count == 3, features.shape[1].intValue == 1024,
            length > 0, length <= features.shape[2].intValue
        else {
            throw DictationInferenceError.incompatibleModel
        }

        let vectors = MLShapedArray<Float>(converting: features)
        let frameFeature = MLFeatureValue(multiArray: frameBuffer)
        var jointProvider = try MLDictionaryFeatureProvider(dictionary: [
            "encoder_step": frameFeature,
            "decoder_step": MLFeatureValue(multiArray: state.projection)
        ])

        var time = 0
        var emissions = 0
        var pieces = [(piece: String, start: TimeInterval, end: TimeInterval)]()
        while time < length {
            vectors.withUnsafeShapedBufferPointer { source, _, strides in
                frameBuffer.withUnsafeMutableBufferPointer(ofType: Float.self) { target, _ in
                    if let srcBase = source.baseAddress, let dstBase = target.baseAddress, strides[1] > 0 {
                        var zero: Float = 0
                        vDSP_vsadd(
                            srcBase.advanced(by: time * strides[2]),
                            vDSP_Stride(strides[1]),
                            &zero,
                            dstBase,
                            1,
                            1024
                        )
                    } else {
                        for channel in 0..<1024 {
                            target[channel] = source[channel * strides[1] + time * strides[2]]
                        }
                    }
                }
            }
            let decision = try DictationTensor.predict(joint, jointProvider)
            let tokens = try DictationTensor.array("token_id", from: decision)
            let durations = try DictationTensor.array("duration", from: decision)
            guard tokens.count > 0, durations.count > 0 else {
                throw DictationInferenceError.incompatibleModel
            }
            let token = tokens[0].intValue
            let duration = durations[0].intValue
            guard (0...blank).contains(token), (0...4).contains(duration) else {
                throw DictationInferenceError.incompatibleModel
            }
            if token != blank {
                if let piece = vocabulary[token], !piece.hasPrefix("<|") {
                    let start = offsetSeconds + Double(time) * frameSeconds
                    let end = offsetSeconds + Double(time + max(1, duration)) * frameSeconds
                    pieces.append((piece, start, end))
                }
                let next = try advanceDecoder(token: token, hidden: state.hidden, cell: state.cell)
                state = DecoderState(hidden: next.hidden, cell: next.cell, projection: next.projection)
                jointProvider = try MLDictionaryFeatureProvider(dictionary: [
                    "encoder_step": frameFeature,
                    "decoder_step": MLFeatureValue(multiArray: state.projection)
                ])
                emissions += 1
            }
            let step = token == blank || emissions >= 10 ? max(1, duration) : duration
            if step > 0 { time += step; emissions = 0 }
        }
        return pieces
    }
}
