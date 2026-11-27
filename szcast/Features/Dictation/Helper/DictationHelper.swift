import Foundation

@main
enum DictationHelper {
    static func main() {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        guard fcntl(output.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { exit(1) }
        let session = DictationInferenceSession()
        do {
            while let request = try DictationWire.read(DictationWire.Request.self, from: input) {
                try DictationTensor.checkParent()
                let validCount = request.prewarmOnly
                    ? request.sampleCount == 0
                    : (1...DictationWire.maximumSamples).contains(request.sampleCount)
                guard validCount, request.directory.isFileURL else {
                    throw DictationInferenceError.invalidAudio
                }
                do {
                    try session.prepare(model: request.model, directory: request.directory)
                } catch {
                    try DictationWire.write(
                        DictationWire.Response(id: request.id, status: .failed), to: output)
                    continue
                }
                try DictationWire.write(DictationWire.Response(id: request.id, status: .ready), to: output)
                if request.prewarmOnly {
                    session.warmupIfNeeded()
                    try DictationWire.write(
                        DictationWire.Response(id: request.id, status: .result), to: output)
                    continue
                }
                try autoreleasepool {
                    let data = try DictationWire.readExactly(
                        request.sampleCount * MemoryLayout<Float>.size, from: input)
                    let samples = [Float](unsafeUninitializedCapacity: request.sampleCount) { buffer, count in
                        data.withUnsafeBytes { bytes in
                            UnsafeMutableRawBufferPointer(buffer).copyMemory(from: bytes)
                        }
                        count = request.sampleCount
                    }
                    guard samples.allSatisfy({ $0.isFinite }) else {
                        throw DictationInferenceError.invalidAudio
                    }
                    do {
                        let timed = try session.transcribe(samples: samples, request: request)
                        try DictationWire.write(
                            DictationWire.Response(
                                id: request.id,
                                status: .result,
                                text: timed.text,
                                words: timed.words,
                                segments: timed.segments,
                                timings: timed.timings
                            ),
                            to: output
                        )
                    } catch {
                        try DictationWire.write(
                            DictationWire.Response(id: request.id, status: .failed), to: output)
                    }
                }
            }
        } catch {
            exit(1)
        }
    }
}
