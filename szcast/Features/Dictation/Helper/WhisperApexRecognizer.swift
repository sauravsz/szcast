import Accelerate
import CoreML
import Foundation

final class WhisperApexRecognizer {
    private struct Config: Decodable {
        let vocabSize: Int
        let eosTokenId: Int
        let bosTokenId: Int
        let decoderStartTokenId: Int
        let maxTargetPositions: Int
    }

    private struct GenerationConfig: Decodable {
        let langToId: [String: Int]?
        let taskToId: [String: Int]?
        let noTimestampsTokenId: Int?
        let suppressTokens: [Int]?
    }

    private let melModel: MLModel
    private let encoder: MLModel
    private let decoder: MLModel
    private let tokenizer: DictationTokenizer
    private let config: Config
    private let langToID: [String: Int]
    private let transcribeTaskID: Int
    private let noTimestampsID: Int
    private let suppressTokens: Set<Int>

    init(directory: URL) throws {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        config = try dec.decode(
            Config.self,
            from: Data(contentsOf: directory.appendingPathComponent("config.json")))

        let genURL = directory.appendingPathComponent("generation_config.json")
        if FileManager.default.fileExists(atPath: genURL.path),
            let gen = try? dec.decode(GenerationConfig.self, from: Data(contentsOf: genURL))
        {
            langToID = gen.langToId ?? [:]
            transcribeTaskID = gen.taskToId?["transcribe"] ?? 50_360
            noTimestampsID = gen.noTimestampsTokenId ?? 50_364
            suppressTokens = Set(gen.suppressTokens ?? [])
        } else {
            langToID = ["<|en|>": 50_259, "<|hi|>": 50_276]
            transcribeTaskID = 50_360
            noTimestampsID = 50_364
            suppressTokens = []
        }

        tokenizer = try DictationTokenizer(
            vocabulary: Data(contentsOf: directory.appendingPathComponent("vocab.json")),
            merges: String(contentsOf: directory.appendingPathComponent("merges.txt"), encoding: .utf8),
            prompts: []
        )
        melModel = try DictationTensor.load("MelSpectrogram", at: directory, units: .cpuOnly)
        encoder = try DictationTensor.load("AudioEncoder", at: directory, units: .cpuAndNeuralEngine)
        decoder = try DictationTensor.load("TextDecoder", at: directory, units: .cpuAndGPU)
    }

    func transcribe(_ samples: [Float], language: String?) throws -> String {
        try transcribeTimed(samples, language: language).text
    }

    func transcribeTimed(_ samples: [Float], language: String?) throws -> TimedTranscript {
        guard !samples.isEmpty, samples.count <= DictationWire.maximumSamples else {
            throw DictationInferenceError.invalidAudio
        }

        let maxSeq = config.maxTargetPositions
        let kvChannels = 5_120
        var chunkTexts = [String]()
        var words = [TranscriptWord]()

        let shortLang = language?.split(separator: "-").first.map { "<|\($0.lowercased())|>" } ?? "<|hi|>"
        let langToken = langToID[shortLang] ?? langToID["<|hi|>"] ?? 50_276
        let promptTokens = [
            config.decoderStartTokenId,
            langToken,
            transcribeTaskID,
            noTimestampsID
        ]

        for range in DictationAudioChunks.ranges(in: samples, maximum: 480_000) {
            let chunkText = try autoreleasepool { () -> String in
                let slice = samples[range]
                let audioArray = try DictationTensor.zeros([480_000], type: .float16)
                var padded = [Float](repeating: 0, count: 480_000)
                for (idx, val) in slice.enumerated() { padded[idx] = val }
                try Self.writeFloat16(padded, to: audioArray)

                let melOut = try DictationTensor.predict(melModel, ["audio": audioArray])
                let melFeatures = try DictationTensor.array("melspectrogram_features", from: melOut)
                let encOut = try DictationTensor.predict(
                    encoder, ["melspectrogram_features": melFeatures])
                let encEmbeds = try DictationTensor.array("encoder_output_embeds", from: encOut)

                let keyCache = try DictationTensor.zeros([1, kvChannels, 1, maxSeq], type: .float16)
                let valueCache = try DictationTensor.zeros([1, kvChannels, 1, maxSeq], type: .float16)
                var paddingMask = [Float](repeating: -10_000, count: maxSeq)
                var updateMask = [Float](repeating: 0, count: maxSeq)

                let kvUpdateArray = try DictationTensor.zeros([1, maxSeq], type: .float16)
                let padMaskArray = try DictationTensor.zeros([1, maxSeq], type: .float16)

                var generated = [Int]()
                var pos = 0

                func stepToken(_ id: Int) throws -> Int {
                    try DictationTensor.checkParent()
                    guard pos < maxSeq else { return config.eosTokenId }
                    paddingMask[pos] = 0
                    updateMask[pos] = 1
                    try Self.writeFloat16(updateMask, to: kvUpdateArray)
                    try Self.writeFloat16(paddingMask, to: padMaskArray)
                    updateMask[pos] = 0

                    let decOut = try DictationTensor.predict(
                        decoder,
                        [
                            "input_ids": DictationTensor.integer(id, shape: [1]),
                            "cache_length": DictationTensor.integer(pos, shape: [1]),
                            "key_cache": keyCache,
                            "value_cache": valueCache,
                            "kv_cache_update_mask": kvUpdateArray,
                            "encoder_output_embeds": encEmbeds,
                            "decoder_key_padding_mask": padMaskArray
                        ]
                    )
                    let keyUpdates = try DictationTensor.array("key_cache_updates", from: decOut)
                    let valueUpdates = try DictationTensor.array("value_cache_updates", from: decOut)
                    Self.scatterCacheColumn(from: keyUpdates, into: keyCache, column: pos, maxSeq: maxSeq, channels: kvChannels)
                    Self.scatterCacheColumn(from: valueUpdates, into: valueCache, column: pos, maxSeq: maxSeq, channels: kvChannels)
                    pos += 1

                    let logits = try DictationTensor.array("logits", from: decOut)
                    var scores = try DictationTensor.floatValues(from: logits)
                    for sup in suppressTokens where sup < scores.count {
                        scores[sup] = -Float.greatestFiniteMagnitude
                    }
                    return scores.indices.max(by: { scores[$0] < scores[$1] }) ?? config.eosTokenId
                }

                var nextToken = config.eosTokenId
                for tok in promptTokens {
                    nextToken = try stepToken(tok)
                }
                while pos < maxSeq && nextToken != config.eosTokenId && nextToken != config.bosTokenId {
                    if nextToken < 50_257 { generated.append(nextToken) }
                    nextToken = try stepToken(nextToken)
                }
                return try tokenizer.decode(generated).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard !chunkText.isEmpty else { continue }
            chunkTexts.append(chunkText)
            let tokens = chunkText.split(whereSeparator: \.isWhitespace).map(String.init)
            let chunkStart = Double(range.lowerBound) / Double(DictationWire.sampleRate)
            let chunkDur = Double(range.count) / Double(DictationWire.sampleRate)
            let step = chunkDur / Double(max(1, tokens.count))
            for (idx, tok) in tokens.enumerated() {
                words.append(TranscriptWord(
                    text: tok, start: chunkStart + Double(idx) * step, end: chunkStart + Double(idx + 1) * step))
            }
        }

        let text = chunkTexts.joined(separator: " ")
        return TimedTranscript(
            text: text,
            words: words,
            segments: TranscriptSegmentBuilder.build(words: words, fallbackText: text)
        )
    }

    private static func writeFloat16(_ source: [Float], to target: MLMultiArray) throws {
        var mutable = source
        try mutable.withUnsafeMutableBufferPointer { srcBuf in
            try target.withUnsafeMutableBytes { dstBytes, _ in
                var src = vImage_Buffer(
                    data: srcBuf.baseAddress!, height: 1, width: vImagePixelCount(source.count),
                    rowBytes: source.count * 4)
                var dst = vImage_Buffer(
                    data: dstBytes.baseAddress!, height: 1, width: vImagePixelCount(source.count),
                    rowBytes: source.count * 2)
                let status = vImageConvert_PlanarFtoPlanar16F(
                    &src, &dst, vImage_Flags(kvImageDoNotTile))
                guard status == kvImageNoError else { throw DictationInferenceError.incompatibleModel }
            }
        }
    }

    private static func scatterCacheColumn(
        from update: MLMultiArray, into cache: MLMultiArray, column: Int, maxSeq: Int, channels: Int
    ) {
        update.withUnsafeBytes { srcRaw in
            cache.withUnsafeMutableBytes { dstRaw, _ in
                let src = srcRaw.bindMemory(to: UInt16.self)
                let dst = dstRaw.bindMemory(to: UInt16.self)
                for ch in 0..<min(channels, src.count) {
                    dst[ch * maxSeq + column] = src[ch]
                }
            }
        }
    }
}
