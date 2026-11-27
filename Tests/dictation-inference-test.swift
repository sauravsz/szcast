import Foundation

@main
struct DictationInferenceTest {
    static func main() throws {
        var tied = [Float16](repeating: -1, count: 64)
        tied[7] = 4
        tied[32] = 4
        var wide = [Float16](repeating: -1, count: 151936)
        wide[151934] = 4
        let fixtures: [[Float16]] = [[-5, -1, -1, -3], [4, 4, -2], [-2, 0, 3], [7], tied, wide]
        for values in fixtures {
            let scores = try DictationTensor.zeros([1, 1, values.count], type: .float16)
            scores.withUnsafeMutableBufferPointer(ofType: Float16.self) { buffer, _ in
                _ = buffer.update(from: values)
            }
            let expected = values.indices.reduce(0) { values[$1] > values[$0] ? $1 : $0 }
            guard try DictationTensor.indexOfMaximum(in: scores) == expected else {
                fatalError("Score selection changed the first maximum")
            }
        }
        for scores in [try DictationTensor.zeros([1, 2]), try DictationTensor.zeros([2, 2], type: .float16)] {
            do {
                _ = try DictationTensor.indexOfMaximum(in: scores)
                fatalError("Score selection accepted an incompatible tensor")
            } catch DictationInferenceError.incompatibleModel {}
        }

        var vocabulary = [String: Int]()
        var extra = 256
        for byte in 0...255 {
            let literal =
                (33...126).contains(byte) || (161...172).contains(byte) || (174...255).contains(byte)
            let scalar = Unicode.Scalar(literal ? byte : extra)!
            if !literal { extra += 1 }
            vocabulary[String(scalar)] = byte
        }
        vocabulary["ab"] = 256
        let prompts = ["ab", "szcast", "é 新 🍋", "two\nlines", "1, 2, 300"]
        let tokenizer = try DictationTokenizer(
            vocabulary: JSONEncoder().encode(vocabulary),
            merges: "#version: 0.2\na b\n", prompts: prompts + ["ab"])
        guard try tokenizer.tokens(for: "ab") == [256] else { fatalError("BPE merge failed") }
        for text in prompts {
            guard try tokenizer.decode(tokenizer.tokens(for: text)) == text else {
                fatalError("Tokenizer round trip failed")
            }
        }
        do {
            _ = try tokenizer.tokens(for: "not prepared")
            fatalError("Tokenizer accepted an unprepared prompt")
        } catch CocoaError.coderInvalidValue {}

        let mel = try DictationMel()
        let silence = try mel.features([Float](repeating: 0, count: 16_000)[...])
        guard silence.frames == 100, silence.values.allSatisfy({ $0 == -1.5 }),
            DictationMel.embeddingCount(frames: 3000) == 390,
            DictationMel.embeddingCount(frames: 1500) == 195
        else { fatalError("Mel shape or normalization failed") }
        for (frequency, expected) in [(440.0, 18), (2500.0, 80)] {
            let samples = (0..<16_000).map { Float(sin(2 * .pi * frequency * Double($0) / 16_000)) }
            let spectrum = try mel.features(samples[...])
            let peak = (0..<128).max { spectrum.values[$0 * 100 + 10] < spectrum.values[$1 * 100 + 10] }!
            guard abs(peak - expected) <= 1 else {
                fatalError("Fourier transform placed energy in the wrong band")
            }
        }
        let paddedAudio = (0..<11_111).map { Float(sin(Double($0) * 0.017)) }
        let padded = try mel.features(paddedAudio[...])
        let baseline = try referenceMel(paddedAudio, length: padded.length)
        guard zip(padded.values, baseline).allSatisfy({ abs($0 - $1) < 0.0001 }) else {
            fatalError("Skipping silent padding changed the mel spectrum")
        }

        let waveform = try DictationSpectrum()
        guard
            waveform.levels(for: [Float](repeating: 0, count: 512)[...]) == [Float](repeating: 0, count: 21),
            waveform.levels(for: [Float]()[...]).allSatisfy({ $0 == 0 })
        else {
            fatalError("Silent audio moved the waveform")
        }
        for (frequency, expected) in [(440.0, 11), (2500.0, 18)] {
            let tone = (0..<800).map { Float(0.2 * sin(2 * .pi * frequency * Double($0) / 16_000)) }
            let levels = waveform.levels(for: tone[...])
            let peak = levels.indices.max { levels[$0] < levels[$1] }!
            guard levels.count == 21, abs(peak - expected) <= 1,
                levels.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                levels == waveform.levels(for: tone.suffix(512))
            else {
                fatalError("Listening bands moved, saturated or retained old samples")
            }
        }

        var samples = [Float](repeating: 0.5, count: 480_001)
        for index in 210_000..<218_000 { samples[index] = 0 }
        let ranges = DictationAudioChunks.ranges(in: samples, maximum: 240_000)
        guard ranges.first?.lowerBound == 0, ranges.last?.upperBound == samples.count,
            ranges.first.map({ (210_000..<218_000).contains($0.upperBound) }) == true,
            ranges.allSatisfy({ !$0.isEmpty && $0.count <= 240_000 }),
            zip(ranges, ranges.dropFirst()).allSatisfy({ $0.upperBound == $1.lowerBound }),
            DictationAudioChunks.ranges(in: [], maximum: 240_000).isEmpty
        else {
            fatalError("Audio chunks lost, repeated or cut samples outside a pause")
        }
        var live = [Float](repeating: 0.5, count: 48_000)
        for index in 40_000..<43_200 { live[index] = 0 }
        guard
            DictationAudioChunks.liveCut(in: live, from: 0, to: live.count) == 41_600,
            DictationAudioChunks.liveCut(
                in: [Float](repeating: 0.5, count: 48_000), from: 0, to: 48_000) == 46_400,
            DictationAudioChunks.liveCut(in: live, from: 46_400, to: live.count) == 46_400,
            DictationAudioChunks.liveCut(in: [], from: 0, to: 0) == 0
        else {
            fatalError("Live insertion cut outside a pause, repeated audio or flushed too little")
        }
        var uttered = [Float](repeating: 0.5, count: 32_000) + [Float](repeating: 0, count: 16_000)
        var steady = [Float](repeating: 0.5, count: 100_000)
        for index in 80_000..<83_200 { steady[index] = 0 }
        guard DictationAudioChunks.liveOverlapStart(in: steady, before: 90_000) == 81_520,
            DictationAudioChunks.liveOverlapStart(
                in: [Float](repeating: 0.5, count: 100_000), before: 90_000) == 58_000,
            DictationAudioChunks.liveOverlapStart(in: steady, before: 10_000) == 0
        else {
            fatalError("Live insertion re-started mid-word although a pause was behind")
        }
        guard
            DictationAudioChunks.endsInPause(in: uttered, from: 0, to: uttered.count),
            !DictationAudioChunks.endsInPause(
                in: [Float](repeating: 0.5, count: 48_000), from: 0, to: 48_000),
            !DictationAudioChunks.endsInPause(
                in: [Float](repeating: 0, count: 48_000), from: 0, to: 48_000),
            !DictationAudioChunks.endsInPause(
                in: [Float](repeating: 0.5, count: 16_000), from: 0, to: 16_000)
        else {
            fatalError("Live insertion flushed speech without a pause, or silence as speech")
        }

        // vDSP 2nd-order Butterworth 80 Hz high-pass, de-click & active-speech loudness conditioning
        let lowHum = (0..<3_200).map { i -> Float in
            let hum = 0.04 * sin(2 * Float.pi * 40 * Float(i) / 16_000)
            let voice = 0.015 * sin(2 * Float.pi * 300 * Float(i) / 16_000)
            return hum + voice
        }
        var withEdgeClick = lowHum
        withEdgeClick[12] = 0.95
        withEdgeClick[withEdgeClick.count - 12] = -0.95
        let conditioned = DictationAudioChunks.conditionForTranscription(withEdgeClick)
        let whisperConditioned = DictationAudioChunks.conditionForTranscription(withEdgeClick, whisperMode: true)
        let silentBuf = [Float](repeating: 0.0001, count: 1600)
        let conditionedSilent = DictationAudioChunks.conditionForTranscription(silentBuf)
        let tinyClick = [Float](repeating: 0.5, count: 1200)
        let realSpeech = (0..<4_800).map { Float(0.05 * sin(2 * Float.pi * 250 * Float($0) / 16_000)) }
        guard conditioned.count == lowHum.count,
              whisperConditioned.count == lowHum.count,
              whisperConditioned.allSatisfy({ abs($0) <= 1.0 }),
              conditioned.allSatisfy({ abs($0) <= 1.0 }),
              abs(conditioned[12]) < 0.35,
              conditionedSilent.allSatisfy({ abs($0) < 0.001 }),
              !DictationAudioChunks.hasUsableSpeechEnergy(tinyClick),
              !DictationAudioChunks.hasUsableSpeechEnergy(silentBuf),
              DictationAudioChunks.hasUsableSpeechEnergy(realSpeech)
        else {
            fatalError("Audio conditioning failed biquad bounds, whisper shelf, speech gate, or silence floor")
        }

        // Backwards-compatible DictationWire.Response timings Codable round-trip
        let legacyJSON = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"status\":\"result\",\"text\":\"hi\",\"words\":[],\"segments\":[]}".utf8)
        let decodedLegacy = try JSONDecoder().decode(DictationWire.Response.self, from: legacyJSON)
        let timedResp = DictationWire.Response(
            id: UUID(),
            status: .result,
            text: "ok",
            timings: DictationStageTimings(vadMs: 12.5, asrMs: 48.0, diarizationMs: 0, totalMs: 61.0)
        )
        let decodedModern = try JSONDecoder().decode(
            DictationWire.Response.self, from: JSONEncoder().encode(timedResp))
        guard decodedLegacy.timings == nil,
              decodedModern.timings?.asrMs == 48.0,
              decodedModern.timings?.vadMs == 12.5
        else {
            fatalError("DictationStageTimings Codable round-trip failed")
        }

        // IndicFlex array vocab + romanized prompt + WhisperApex ISO codes
        let vocabJSON = Data("""
        ["<pad>","<bos>","<eos>","<s>","</s>","<|bn|>","<|hi|>","<|romanized|>","<|noromanized|>","▁","ami"]
        """.utf8)
        let parsed = try IndicFlexRecognizer.parseVocabulary(from: vocabJSON)
        guard parsed.idToToken[9] == "▁",
              parsed.idToToken[10] == "ami",
              parsed.romanizedID == 7,
              parsed.noRomanizedID == 8
        else {
            fatalError("IndicFlex array vocabulary parsing failed")
        }
        let promptsByLang = ["bn": [1, 5, 8], "hi": [1, 6, 8]]
        guard
            IndicFlexRecognizer.romanizedPrompt(
                language: "Bengali", promptIdsByLang: promptsByLang,
                fallbackBosID: 1, romanizedID: parsed.romanizedID, noRomanizedID: parsed.noRomanizedID
            ) == [1, 5, 7],
            IndicFlexRecognizer.romanizedPrompt(
                language: "en", promptIdsByLang: promptsByLang,
                fallbackBosID: 1, romanizedID: parsed.romanizedID, noRomanizedID: parsed.noRomanizedID
            ) == [1, 5, 7],
            IndicFlexRecognizer.romanizedPrompt(
                language: "Hindi", promptIdsByLang: promptsByLang,
                fallbackBosID: 1, romanizedID: parsed.romanizedID, noRomanizedID: parsed.noRomanizedID
            ) == [1, 6, 7],
            DictationLanguage.isoCode(for: "Bengali") == "bn",
            DictationLanguage.isoCode(for: "Hindi") == "hi",
            DictationLanguage.isoCode(for: "Banglish") == "bn",
            DictationLanguage.isoCode(for: "Hinglish") == "hi"
        else {
            fatalError("IndicFlex romanized prompt or Whisper ISO resolution failed")
        }

        // SraVaani SentencePiece protobuf parsing + Model metadata check
        let tok1 = Data("<unk>".utf8)
        let spPiece = Data([0x0A, UInt8(tok1.count)]) + tok1 + Data([0x15, 0, 0, 0, 0, 0x18, 0x02])
        let tok2 = Data("▁hi".utf8)
        let spPiece2 = Data([0x0A, UInt8(tok2.count)]) + tok2
        let protoData = Data([0x0A, UInt8(spPiece.count)]) + spPiece
            + Data([0x0A, UInt8(spPiece2.count)]) + spPiece2
        let spVocab = try SraVaaniRecognizer.parseSentencePieceVocabulary(from: protoData)
        guard spVocab[0] == "<unk>", spVocab[1] == "▁hi",
              DictationModel.sravaani.repository == "spashii/SraVaani-1.0-CoreML",
              DictationModel.sravaani.components.contains("SraVaaniEncoder.mlmodelc"),
              DictationModel.v2.parakeetConfiguration?.blankToken == 1024,
              DictationModel.ctc.isParakeetCTC,
              DictationModel.ctcSmall.isParakeetCTC,
              DictationModel.ctcSmall.repository == "FluidInference/parakeet-ctc-110m-coreml"
        else {
            fatalError("SraVaani / Parakeet v2 / Parakeet CTC metadata check failed")
        }

        // Phase 5: Multi-chunk (45s) boundary continuity & consecutive Mel consistency across chunks
        var longSpeech = [Float](repeating: 0.4, count: 720_000)
        for silentStart in [212_000, 442_000, 668_000] {
            for s in silentStart..<(silentStart + 12_000) { longSpeech[s] = 0 }
        }
        let longChunks = DictationAudioChunks.ranges(in: longSpeech, maximum: 240_000)
        guard longChunks.count == 4,
              longChunks.first?.lowerBound == 0,
              longChunks.last?.upperBound == 720_000,
              zip(longChunks, longChunks.dropFirst()).allSatisfy({ $0.upperBound == $1.lowerBound }),
              (212_000...224_000).contains(longChunks[0].upperBound),
              (442_000...454_000).contains(longChunks[1].upperBound),
              (668_000...680_000).contains(longChunks[2].upperBound)
        else {
            fatalError("45s multi-chunk boundaries split mid-speech or broke continuity: \(longChunks)")
        }
        let chunkA = try mel.features(conditioned[..<1600])
        let chunkB = try mel.features(conditioned[..<1600])
        guard chunkA.frames == chunkB.frames && zip(chunkA.values, chunkB.values).allSatisfy({ abs($0 - $1) < 1e-6 }) else {
            fatalError("Repeated Mel feature extraction drifted")
        }

        print(
            "Dictation scores, tokenizer, FFT, mel features, bands, chunks, live cuts & Indic prompts passed"
        )
    }

    private static func referenceMel(_ samples: [Float], length: Int) throws -> [Float] {
        let padded = samples + [Float](repeating: 0, count: length * 160 - samples.count)
        return try DictationMel().features(padded[...]).values
    }
}
