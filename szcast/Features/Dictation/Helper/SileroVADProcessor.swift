import CoreML
import Foundation

final class SileroVADProcessor {
    static let windowSamples = 4_160
    static let hopSamples = 4_096

    private let model: MLModel

    init(directory: URL) throws {
        model = try DictationTensor.load(
            "silero-vad-unified-256ms-v6.2.1", at: directory, units: .cpuAndNeuralEngine)
    }

    func speechSpans(in samples: [Float], threshold: Float = 0.45) throws -> [DictationVADChunker.SpeechSpan] {
        guard !samples.isEmpty else { return [] }
        let input = try DictationTensor.zeros([1, Self.windowSamples])
        var hidden = try DictationTensor.zeros([1, 128])
        var cell = try DictationTensor.zeros([1, 128])
        var probabilities = [Float]()
        probabilities.reserveCapacity((samples.count + Self.hopSamples - 1) / Self.hopSamples)

        var cursor = 0
        while cursor < samples.count {
            try autoreleasepool {
                input.withUnsafeMutableBufferPointer(ofType: Float.self) { buf, _ in
                    buf.initialize(repeating: 0)
                    let prefixStart = max(0, cursor - 64)
                    var writeIdx = 0
                    if cursor < 64 {
                        writeIdx = 64 - cursor
                    } else {
                        for idx in prefixStart..<cursor {
                            buf[writeIdx] = samples[idx]
                            writeIdx += 1
                        }
                    }
                    let copyCount = min(Self.hopSamples, samples.count - cursor)
                    for idx in 0..<copyCount {
                        buf[writeIdx + idx] = samples[cursor + idx]
                    }
                }
                let output = try DictationTensor.predict(
                    model,
                    [
                        "audio_input": input,
                        "hidden_state": hidden,
                        "cell_state": cell
                    ]
                )
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
            threshold: threshold
        )
    }
}
