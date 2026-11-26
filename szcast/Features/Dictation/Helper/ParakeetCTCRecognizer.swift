import CoreML
import Foundation

/// Runs offline English CoreML CTC ASR for FluidInference Parakeet-CTC (0.6B INT8 and 110M).
final class ParakeetCTCRecognizer {
    private let melSpectrogram: MLModel
    private let encoder: MLModel
    private let vocabulary: [Int: String]
    private static let windowSamples = 240_000
    private static let blankID = 1024

    init(directory: URL) throws {
        let fm = FileManager.default
        let melName = fm.fileExists(atPath: directory.appendingPathComponent("MelSpectrogram_int8.mlmodelc").path)
            ? "MelSpectrogram_int8" : "MelSpectrogram"
        let encName = fm.fileExists(atPath: directory.appendingPathComponent("AudioEncoder_int8.mlmodelc").path)
            ? "AudioEncoder_int8" : "AudioEncoder"

        melSpectrogram = try DictationTensor.load(melName, at: directory, units: .cpuOnly)
        encoder = try DictationTensor.load(encName, at: directory, units: .cpuAndNeuralEngine)

        let rawVocab = try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: directory.appendingPathComponent("vocab.json"))
        )
        vocabulary = Dictionary(
            uniqueKeysWithValues: rawVocab.compactMap { key, value in
                guard let id = Int(key) else { return nil }
                return (id, value)
            }
        )
    }

    func transcribeTimed(_ samples: [Float], language: String?) throws -> TimedTranscript {
        guard !samples.isEmpty, samples.count <= DictationWire.maximumSamples else {
            throw DictationInferenceError.invalidAudio
        }

        var allPieces = [(piece: String, start: TimeInterval, end: TimeInterval)]()
        var chunkTexts = [String]()
        for range in DictationAudioChunks.ranges(in: samples, maximum: Self.windowSamples) {
            let offsetSeconds = Double(range.lowerBound) / Double(DictationWire.sampleRate)
            let chunkPieces = try autoreleasepool { try decodeChunk(samples[range], offsetSeconds: offsetSeconds) }
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

    private func decodeChunk(
        _ samples: ArraySlice<Float>,
        offsetSeconds: TimeInterval
    ) throws -> [(piece: String, start: TimeInterval, end: TimeInterval)] {
        let audioDesc = melSpectrogram.modelDescription.inputDescriptionsByName["audio"]
        let dataType: MLMultiArrayDataType = audioDesc?.multiArrayConstraint?.dataType == .float16 ? .float16 : .float32
        let shape: [Int] = audioDesc?.multiArrayConstraint?.shape.count == 2
            ? [1, Self.windowSamples] : [Self.windowSamples]

        let audio = try DictationTensor.zeros(shape, type: dataType)
        if dataType == .float16 {
            audio.withUnsafeMutableBufferPointer(ofType: Float16.self) { buffer, _ in
                for (idx, sample) in samples.enumerated() { buffer[idx] = Float16(sample) }
            }
        } else {
            audio.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
                for (idx, sample) in samples.enumerated() { buffer[idx] = sample }
            }
        }

        var melInputs: [String: MLFeatureValue] = ["audio": MLFeatureValue(multiArray: audio)]
        if melSpectrogram.modelDescription.inputDescriptionsByName["audio_length"] != nil {
            melInputs["audio_length"] = MLFeatureValue(multiArray: try DictationTensor.integer(samples.count))
        }
        let melOut = try melSpectrogram.prediction(from: MLDictionaryFeatureProvider(dictionary: melInputs))
        guard let melFeatures = melOut.featureValue(for: "melspectrogram_features")?.multiArrayValue else {
            throw DictationInferenceError.incompatibleModel
        }

        var encInputs: [String: MLFeatureValue] = ["melspectrogram_features": MLFeatureValue(multiArray: melFeatures)]
        let encDescriptions = encoder.modelDescription.inputDescriptionsByName
        if encDescriptions["mel_length"] != nil {
            let melLen = melOut.featureValue(for: "mel_length")?.multiArrayValue?[0].intValue
                ?? melFeatures.shape.last?.intValue
                ?? 1501
            encInputs["mel_length"] = MLFeatureValue(multiArray: try DictationTensor.integer(melLen))
        }
        if encDescriptions["input_1"] != nil {
            let flag = try DictationTensor.zeros([1, 1, 1, 1], type: .float16)
            flag[0] = 1
            encInputs["input_1"] = MLFeatureValue(multiArray: flag)
        }

        let encOut = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: encInputs))
        guard let logits = encOut.featureValue(for: "ctc_head_raw_output")?.multiArrayValue
            ?? encOut.featureValue(for: "ctc_head_output")?.multiArrayValue
        else {
            throw DictationInferenceError.incompatibleModel
        }

        let rank = logits.shape.count
        guard rank == 3 || rank == 4 else { throw DictationInferenceError.incompatibleModel }
        let timeAxis = rank == 3 ? 1 : 3
        let vocabAxis = rank == 3 ? 2 : 1
        let totalFrames = logits.shape[timeAxis].intValue
        let vocabCount = logits.shape[vocabAxis].intValue
        guard totalFrames > 0, vocabCount > Self.blankID else {
            throw DictationInferenceError.incompatibleModel
        }

        let encLen = encOut.featureValue(for: "encoder_length")?.multiArrayValue?[0].intValue
            ?? max(1, Int(ceil(Double(samples.count) / Double(Self.windowSamples) * Double(totalFrames))))
        let activeFrames = min(totalFrames, max(1, encLen))
        let timeStride = logits.strides[timeAxis].intValue
        let vocabStride = logits.strides[vocabAxis].intValue
        let frameSeconds = (Double(samples.count) / Double(DictationWire.sampleRate)) / Double(activeFrames)

        var pieces = [(piece: String, start: TimeInterval, end: TimeInterval)]()
        var previous = -1

        func decodeFrames<Scalar>(as _: Scalar.Type, value: (Scalar) -> Float) {
            logits.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: Scalar.self) else { return }
                for frameIdx in 0..<activeFrames {
                    let rowBase = frameIdx * timeStride
                    var bestID = Self.blankID
                    var bestScore: Float = -.infinity
                    for tokID in 0..<vocabCount {
                        let score = value(base[rowBase + tokID * vocabStride])
                        if score > bestScore { bestScore = score; bestID = tokID }
                    }
                    if bestID != Self.blankID && bestID != previous,
                       let piece = vocabulary[bestID], !piece.isEmpty, piece != "<unk>"
                    {
                        let start = offsetSeconds + Double(frameIdx) * frameSeconds
                        pieces.append((piece, start, start + frameSeconds))
                    }
                    previous = bestID
                }
            }
        }

        if logits.dataType == .float16 {
            decodeFrames(as: Float16.self) { Float($0) }
        } else {
            decodeFrames(as: Float.self) { $0 }
        }
        return pieces
    }
}
