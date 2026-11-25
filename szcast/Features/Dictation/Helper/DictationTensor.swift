import Accelerate
import CoreML
import Foundation

enum DictationInferenceError: Error {
    case incompatibleModel, invalidAudio, outputLimit, parentExited
}

enum DictationTensor {
    static func zeros(_ shape: [Int], type: MLMultiArrayDataType = .float32) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: type)
        array.withUnsafeMutableBytes { bytes, _ in
            _ = bytes.initializeMemory(as: UInt8.self, repeating: 0)
        }
        return array
    }

    static func integer(_ value: Int, shape: [Int] = [1]) throws -> MLMultiArray {
        let array = try zeros(shape, type: .int32)
        array[0] = NSNumber(value: value)
        return array
    }

    static func predict(_ model: MLModel, _ inputs: [String: MLMultiArray]) throws -> MLFeatureProvider {
        try checkParent()
        return try model.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
    }

    static func array(_ name: String, from features: MLFeatureProvider) throws -> MLMultiArray {
        guard let array = features.featureValue(for: name)?.multiArrayValue else {
            throw DictationInferenceError.incompatibleModel
        }
        return array
    }

    static func indexOfMaximum(in scores: MLMultiArray) throws -> Int {
        guard scores.count > 0, scores.dataType == .float16,
            scores.shape.last?.intValue == scores.count, scores.strides.last?.intValue == 1
        else {
            throw DictationInferenceError.incompatibleModel
        }
        let values = try [Float](unsafeUninitializedCapacity: scores.count) { values, initialized in
            try scores.withUnsafeBytes { bytes in
                var source = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: bytes.baseAddress!),
                    height: 1, width: vImagePixelCount(scores.count), rowBytes: scores.count * 2)
                var destination = vImage_Buffer(
                    data: values.baseAddress!,
                    height: 1, width: vImagePixelCount(scores.count), rowBytes: scores.count * 4)
                let status = vImageConvert_Planar16FtoPlanarF(
                    &source, &destination, vImage_Flags(kvImageDoNotTile))
                guard status == kvImageNoError else {
                    throw DictationInferenceError.incompatibleModel
                }
            }
            initialized = scores.count
        }
        return Int(vDSP.indexOfMaximum(values).0)
    }

    static func load(_ name: String, at directory: URL, units: MLComputeUnits = .all) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = units
        if units == .cpuAndGPU || units == .all {
            configuration.allowLowPrecisionAccumulationOnGPU = true
        }
        let compiledURL = directory.appendingPathComponent(
            name.hasSuffix(".mlmodelc") ? name : name + ".mlmodelc"
        )
        if FileManager.default.fileExists(atPath: compiledURL.path) {
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }
        let packageName = name.hasSuffix(".mlpackage") ? name : name + ".mlpackage"
        let packageURL = directory.appendingPathComponent(packageName)
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }
        let tempCompiled = try MLModel.compileModel(at: packageURL)
        let cachedCompiled = packageURL.deletingPathExtension().appendingPathExtension("mlmodelc")
        if !FileManager.default.fileExists(atPath: cachedCompiled.path) {
            try? FileManager.default.moveItem(at: tempCompiled, to: cachedCompiled)
        }
        let loadURL = FileManager.default.fileExists(atPath: cachedCompiled.path) ? cachedCompiled : tempCompiled
        return try MLModel(contentsOf: loadURL, configuration: configuration)
    }

    static func floatValues(from array: MLMultiArray) throws -> [Float] {
        guard array.count > 0 else { return [] }
        switch array.dataType {
        case .float32:
            var out = [Float](repeating: 0, count: array.count)
            array.withUnsafeBufferPointer(ofType: Float.self) { buf in
                for i in 0..<min(out.count, buf.count) { out[i] = buf[i] }
            }
            return out
        case .float16:
            return try [Float](unsafeUninitializedCapacity: array.count) { values, initialized in
                try array.withUnsafeBytes { bytes in
                    var source = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: bytes.baseAddress!),
                        height: 1, width: vImagePixelCount(array.count), rowBytes: array.count * 2)
                    var destination = vImage_Buffer(
                        data: values.baseAddress!,
                        height: 1, width: vImagePixelCount(array.count), rowBytes: array.count * 4)
                    let status = vImageConvert_Planar16FtoPlanarF(
                        &source, &destination, vImage_Flags(kvImageDoNotTile))
                    guard status == kvImageNoError else {
                        throw DictationInferenceError.incompatibleModel
                    }
                }
                initialized = array.count
            }
        default:
            return (0..<array.count).map { array[$0].floatValue }
        }
    }

    static func checkParent() throws {
        guard getppid() != 1 else { throw DictationInferenceError.parentExited }
    }
}
