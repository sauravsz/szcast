import CoreML
import Foundation

final class IndicFlexRecognizer {
    private struct Metadata: Decodable {
        let chunkSeconds: Double?
        let vocabSize: Int?
        let maxCacheSeqLen: Int?
    }

    private struct TokenizerConfig: Decodable {
        let bosId: Int
        let eosId: Int
        let padId: Int
        let promptIdsByLang: [String: [Int]]
    }

    private let preprocessor: MLModel
    private let encoder: MLModel
    private let decoder: MLModel
    private let idToToken: [Int: String]
    private let tokenizerConfig: TokenizerConfig
    private let metadata: Metadata
    private let romanizedTokenID: Int?
    private let noRomanizedTokenID: Int?

    init(directory: URL) throws {
        let int8Dir = FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("int8/metadata.json").path
        ) ? directory.appendingPathComponent("int8") : directory

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        metadata = try dec.decode(
            Metadata.self,
            from: Data(contentsOf: int8Dir.appendingPathComponent("metadata.json")))
        tokenizerConfig = try dec.decode(
            TokenizerConfig.self,
            from: Data(contentsOf: int8Dir.appendingPathComponent("tokenizer_config.json")))

        let vocabData = try Data(contentsOf: int8Dir.appendingPathComponent("vocab.json"))
        let parsed = try Self.parseVocabulary(from: vocabData)
        idToToken = parsed.idToToken
        romanizedTokenID = parsed.romanizedID
        noRomanizedTokenID = parsed.noRomanizedID

        preprocessor = try DictationTensor.load("indic_flex_preprocessor", at: int8Dir, units: .cpuOnly)
        encoder = try DictationTensor.load("indic_flex_encoder", at: int8Dir, units: .all)
        // CoreML's stateful GPU/MPSGraph path overflows FP16 on this int8 decoder; CPU FP32 decodes cleanly.
        decoder = try DictationTensor.load(
            "indic_flex_decoder_stateful", at: int8Dir, units: .cpuOnly)
    }

    /// Parses `vocab.json` supporting both array (`[String]`) and object (`[String: Int]`) layouts.
    static func parseVocabulary(
        from data: Data
    ) throws -> (idToToken: [Int: String], romanizedID: Int?, noRomanizedID: Int?) {
        var reverse = [Int: String]()
        if let list = try? JSONDecoder().decode([String].self, from: data) {
            for (idx, piece) in list.enumerated() { reverse[idx] = piece }
        } else if let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
            for (piece, idx) in dict { reverse[idx] = piece }
        } else {
            throw DictationInferenceError.incompatibleModel
        }

        var romanizedID: Int?
        var noRomanizedID: Int?
        for (idx, piece) in reverse {
            if piece == "<|romanized|>" { romanizedID = idx }
            else if piece == "<|noromanized|>" { noRomanizedID = idx }
        }
        return (reverse, romanizedID, noRomanizedID)
    }

    /// Resolves the prompt sequence, swapping `<|noromanized|>` for `<|romanized|>` for Banglish/Hinglish.
    static func romanizedPrompt(
        language: String?,
        promptIdsByLang: [String: [Int]],
        fallbackBosID: Int,
        romanizedID: Int?,
        noRomanizedID: Int?
    ) -> [Int] {
        let iso = DictationLanguage.isoCode(for: language) ?? "bn"
        let basePrompt = promptIdsByLang[iso]
            ?? promptIdsByLang["bn"]
            ?? promptIdsByLang["hi"]
            ?? [fallbackBosID]
        guard let romanizedID, let noRomanizedID else { return basePrompt }
        return basePrompt.map { $0 == noRomanizedID ? romanizedID : $0 }
    }

    func transcribe(_ samples: [Float], language: String?) throws -> String {
        try transcribeTimed(samples, language: language).text
    }

    func transcribeTimed(_ samples: [Float], language: String?) throws -> TimedTranscript {
        guard !samples.isEmpty, samples.count <= DictationWire.maximumSamples else {
            throw DictationInferenceError.invalidAudio
        }

        let chunkSamples = Int((metadata.chunkSeconds ?? 30.0) * Double(DictationWire.sampleRate))
        let maxDecode = metadata.maxCacheSeqLen ?? 320
        let prompt = Self.romanizedPrompt(
            language: language,
            promptIdsByLang: tokenizerConfig.promptIdsByLang,
            fallbackBosID: tokenizerConfig.bosId,
            romanizedID: romanizedTokenID,
            noRomanizedID: noRomanizedTokenID
        )

        var chunkTexts = [String]()
        var words = [TranscriptWord]()

        for range in DictationAudioChunks.ranges(in: samples, maximum: min(480_000, chunkSamples)) {
            let decodedText = try autoreleasepool { () -> String in
                let slice = samples[range]
                let audioShape = expectedShape(model: preprocessor, input: "audio", fallback: [1, chunkSamples])
                let targetLen = audioShape.last ?? slice.count
                let audio = try DictationTensor.zeros([1, max(slice.count, targetLen)])
                audio.withUnsafeMutableBufferPointer(ofType: Float.self) { dst, _ in
                    dst.initialize(repeating: 0)
                    for (idx, val) in slice.enumerated() where idx < dst.count { dst[idx] = val }
                }

                let prepOut = try DictationTensor.predict(
                    preprocessor,
                    [
                        "audio": audio,
                        "sample_lens": DictationTensor.integer(slice.count, shape: [1])
                    ]
                )
                let features = try DictationTensor.array("features", from: prepOut)
                let featLens = try DictationTensor.array("feat_lens", from: prepOut)
                let validFeatFrames = featLens[0].intValue
                let melFrames = features.shape.last?.intValue ?? validFeatFrames

                let attnMask = try DictationTensor.zeros([1, melFrames], type: .int32)
                attnMask.withUnsafeMutableBufferPointer(ofType: Int32.self) { dst, _ in
                    dst.initialize(repeating: 0)
                    for i in 0..<min(validFeatFrames, melFrames) { dst[i] = 1 }
                }
                let encOut = try DictationTensor.predict(
                    encoder,
                    ["input_features": features, "attention_mask": attnMask]
                )
                let encStates = try DictationTensor.array("encoder_states", from: encOut)
                let encLens = try DictationTensor.array("encoder_lengths", from: encOut)
                let encLen = encLens[0].intValue
                let encTime = encStates.shape.count >= 2 ? encStates.shape[1].intValue : encLen

                let crossMask = try DictationTensor.zeros([1, 1, 1, encTime])
                crossMask.withUnsafeMutableBufferPointer(ofType: Float.self) { dst, _ in
                    for i in 0..<encTime { dst[i] = i < encLen ? 0 : -10_000 }
                }

                let state = decoder.makeState()
                var pos = 0

                func stepToken(_ tokenID: Int) throws -> [Float] {
                    try DictationTensor.checkParent()
                    guard pos < maxDecode else { return [] }
                    let endStep = pos + 1
                    let selfMask = try DictationTensor.zeros([1, 1, 1, endStep])
                    let pred = try decoder.prediction(
                        from: MLDictionaryFeatureProvider(dictionary: [
                            "input_ids": DictationTensor.integer(tokenID, shape: [1, 1]),
                            "position_ids": DictationTensor.integer(pos, shape: [1, 1]),
                            "encoder_states": encStates,
                            "cross_mask": crossMask,
                            "self_attn_mask": selfMask
                        ]),
                        using: state
                    )
                    pos = endStep
                    return try DictationTensor.floatValues(from: DictationTensor.array("logits", from: pred))
                }

                func prefillPrompt(_ prompt: [Int]) throws -> [Float] {
                    try DictationTensor.checkParent()
                    let q = min(prompt.count, maxDecode)
                    guard q > 0 else { return [] }
                    let inputIDs = try DictationTensor.zeros([1, q], type: .int32)
                    let posIDs = try DictationTensor.zeros([1, q], type: .int32)
                    inputIDs.withUnsafeMutableBufferPointer(ofType: Int32.self) { dst, _ in
                        for (idx, tok) in prompt.prefix(q).enumerated() { dst[idx] = Int32(tok) }
                    }
                    posIDs.withUnsafeMutableBufferPointer(ofType: Int32.self) { dst, _ in
                        for idx in 0..<q { dst[idx] = Int32(idx) }
                    }
                    let selfMask = try DictationTensor.zeros([1, 1, q, q])
                    selfMask.withUnsafeMutableBufferPointer(ofType: Float.self) { dst, _ in
                        for row in 0..<q {
                            for col in 0..<q {
                                dst[row * q + col] = col <= row ? 0 : -10_000
                            }
                        }
                    }
                    let pred = try decoder.prediction(
                        from: MLDictionaryFeatureProvider(dictionary: [
                            "input_ids": inputIDs,
                            "position_ids": posIDs,
                            "encoder_states": encStates,
                            "cross_mask": crossMask,
                            "self_attn_mask": selfMask
                        ]),
                        using: state
                    )
                    pos = q
                    let logits = try DictationTensor.array("logits", from: pred)
                    let values = try DictationTensor.floatValues(from: logits)
                    let vocabSize = logits.shape.last?.intValue ?? 0
                    guard vocabSize > 0, values.count >= q * vocabSize else { return [] }
                    return Array(values[((q - 1) * vocabSize)..<(q * vocabSize)])
                }

                var scores = try prefillPrompt(prompt)
                var pieces = [String]()
                while pos < maxDecode, let nextID = scores.indices.max(by: { scores[$0] < scores[$1] }) {
                    if nextID == tokenizerConfig.eosId || nextID == tokenizerConfig.padId { break }
                    if let piece = idToToken[nextID], nextID >= 1151,
                       !(piece.hasPrefix("<|") && piece.hasSuffix("|>")) {
                        pieces.append(piece)
                    }
                    scores = try stepToken(nextID)
                }
                return pieces.joined()
                    .replacingOccurrences(of: "▁", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard !decodedText.isEmpty else { continue }
            chunkTexts.append(decodedText)
            let toks = decodedText.split(whereSeparator: \.isWhitespace).map(String.init)
            let chunkStart = Double(range.lowerBound) / Double(DictationWire.sampleRate)
            let chunkDur = Double(range.count) / Double(DictationWire.sampleRate)
            let step = chunkDur / Double(max(1, toks.count))
            for (idx, tok) in toks.enumerated() {
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

    private func expectedShape(model: MLModel, input: String, fallback: [Int]) -> [Int] {
        if let constraint = model.modelDescription.inputDescriptionsByName[input]?.multiArrayConstraint,
            !constraint.shape.isEmpty
        {
            return constraint.shape.map(\.intValue)
        }
        return fallback
    }
}
