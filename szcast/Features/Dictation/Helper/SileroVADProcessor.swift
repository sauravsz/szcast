import CoreML
import Foundation

final class SileroVADProcessor {
    static let windowSamples = 4_160
    static let hopSamples = 4_096

    private let model: MLModel
    private let inputBuffer: MLMultiArray

    init(directory: URL) throws {
        model = try DictationTensor.load(
            "silero-vad-unified-256ms-v6.2.1", at: directory, units: .cpuAndNeuralEngine)
        inputBuffer = try DictationTensor.zeros([1, Self.windowSamples])
    }

    func speechSpans(in samples: [Float], threshold: Float = 0.45) throws -> [DictationVADChunker.SpeechSpan] {
        guard !samples.isEmpty else { return [] }
        var hidden = try DictationTensor.zeros([1, 128])
        var cell = try DictationTensor.zeros([1, 128])
        let inputFeature = MLFeatureValue(multiArray: inputBuffer)
        var probabilities = [Float]()
        probabilities.reserveCapacity((samples.count + Self.hopSamples - 1) / Self.hopSamples)

        var cursor = 0
        while cursor < samples.count {
            try autoreleasepool {
                inputBuffer.withUnsafeMutableBufferPointer(ofType: Float.self) { buf, _ in
                    buf.initialize(repeating: 0)
                    guard let dstBase = buf.baseAddress else { return }
                    samples.withUnsafeBufferPointer { src in
                        guard let srcBase = src.baseAddress else { return }
                        let writeOffset: Int
                        if cursor < 64 {
                            writeOffset = 64 - cursor
                        } else {
                            dstBase.update(from: srcBase.advanced(by: cursor - 64), count: 64)
                            writeOffset = 64
                        }
                        let copyCount = min(Self.hopSamples, samples.count - cursor)
                        if copyCount > 0 {
                            dstBase.advanced(by: writeOffset).update(from: srcBase.advanced(by: cursor), count: copyCount)
                        }
                    }
                }
                let provider = try MLDictionaryFeatureProvider(dictionary: [
                    "audio_input": inputFeature,
                    "hidden_state": MLFeatureValue(multiArray: hidden),
                    "cell_state": MLFeatureValue(multiArray: cell)
                ])
                let output = try DictationTensor.predict(model, provider)
                let vad = try DictationTensor.array("vad_output", from: output)
                probabilities.append(vad[0].floatValue)
                hidden = try DictationTensor.array("new_hidden_state", from: output)
                cell = try DictationTensor.array("new_cell_state", from: output)
            }
            cursor += Self.hopSamples
        }

        return DictationVADChunker.speechSpans(
            probabilities: probabilities,
            hopSamples: Self.hopSamples,
            windowSamples: Self.windowSamples,
            totalSamples: samples.count,
            threshold: threshold,
            padSamples: 6_400,
            mergeGapSamples: 9_600
        )
    }
}
