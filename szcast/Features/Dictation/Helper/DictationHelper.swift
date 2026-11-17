import CoreML
import Foundation

protocol DictationRecognizer {
    func transcribe(_ samples: [Float], language: String?) throws -> String
}

extension QwenRecognizer: DictationRecognizer {}
extension ParakeetRecognizer: DictationRecognizer {
    func transcribe(_ samples: [Float], language: String?) throws -> String {
        try transcribe(samples)
    }
}

final class SraVaaniRecognizer: DictationRecognizer {
    private let recognizer: ParakeetRecognizer

    init(directory: URL) throws {
        recognizer = try ParakeetRecognizer(directory: directory, model: .sravaani)
    }

    func transcribe(_ samples: [Float], language: String?) throws -> String {
        try recognizer.transcribe(samples)
    }
}

final class SraVaaniLiveRecognizer: DictationRecognizer {
    private let encoder: MLModel
    private let decoder: MLModel

    init(directory: URL) throws {
        encoder = try DictationTensor.load("encoder", at: directory, units: .all)
        decoder = try DictationTensor.load("decoder", at: directory, units: .all)
    }

    func transcribe(_ samples: [Float], language: String?) throws -> String {
        return ""
    }
}

final class WhisperApexRecognizer: DictationRecognizer {
    private let encoder: MLModel
    private let decoder: MLModel

    init(directory: URL) throws {
        encoder = try DictationTensor.load("AudioEncoder", at: directory, units: .all)
        decoder = try DictationTensor.load("TextDecoder", at: directory, units: .all)
    }

    func transcribe(_ samples: [Float], language: String?) throws -> String {
        return ""
    }
}

final class IndicFlexRecognizer: DictationRecognizer {
    private let encoder: MLModel
    private let decoder: MLModel

    init(directory: URL) throws {
        encoder = try DictationTensor.load("encoder", at: directory, units: .all)
        decoder = try DictationTensor.load("decoder", at: directory, units: .all)
    }

    func transcribe(_ samples: [Float], language: String?) throws -> String {
        return ""
    }
}

@main
enum DictationHelper {
    static func main() {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        guard fcntl(output.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { exit(1) }
        var recognizer: (any DictationRecognizer)?
        var loaded: DictationModel?
        do {
            while let request = try DictationWire.read(DictationWire.Request.self, from: input) {
                try DictationTensor.checkParent()
                guard (1...DictationWire.maximumSamples).contains(request.sampleCount),
                    request.directory.isFileURL
                else {
                    throw DictationInferenceError.invalidAudio
                }
                if loaded != request.model {
                    recognizer = nil
                    loaded = nil
                    do {
                        recognizer = try autoreleasepool { () throws -> any DictationRecognizer in
                            switch request.model {
                            case .qwenSmall, .qwenLarge:
                                return try QwenRecognizer(directory: request.directory)
                            case .ultra, .redux:
                                return try ParakeetRecognizer(directory: request.directory, model: request.model)
                            case .sravaani:
                                return try SraVaaniRecognizer(directory: request.directory)
                            case .sravaaniLive:
                                return try SraVaaniLiveRecognizer(directory: request.directory)
                            case .whisperApex:
                                return try WhisperApexRecognizer(directory: request.directory)
                            case .indicFlex:
                                return try IndicFlexRecognizer(directory: request.directory)
                            }
                        }
                        loaded = request.model
                    } catch {
                        try DictationWire.write(
                            DictationWire.Response(id: request.id, status: .failed), to: output)
                        continue
                    }
                }
                guard let recognizer else { throw DictationInferenceError.incompatibleModel }
                try DictationWire.write(DictationWire.Response(id: request.id, status: .ready), to: output)
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
                        let text = try recognizer.transcribe(samples, language: request.language)
                        try DictationWire.write(
                            DictationWire.Response(id: request.id, status: .result, text: text), to: output)
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
