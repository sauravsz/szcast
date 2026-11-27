import Foundation

protocol DictationRecognizer {
    func transcribeTimed(_ samples: [Float], language: String?) throws -> TimedTranscript
    func warmupIfNeeded()
}

extension DictationRecognizer {
    func warmupIfNeeded() {}
}

extension ParakeetRecognizer: DictationRecognizer {
    func transcribeTimed(_ samples: [Float], language: String?) throws -> TimedTranscript {
        try transcribeTimed(samples)
    }
}

extension NemotronRecognizer: DictationRecognizer {
    func transcribeTimed(_ samples: [Float], language: String?) throws -> TimedTranscript {
        try transcribeTimed(samples)
    }
}

extension QwenRecognizer: DictationRecognizer {}
extension WhisperApexRecognizer: DictationRecognizer {}
extension IndicFlexRecognizer: DictationRecognizer {}
extension SraVaaniRecognizer: DictationRecognizer {}
extension ParakeetCTCRecognizer: DictationRecognizer {}

final class DictationInferenceSession {
    private var loadedModel: DictationModel?
    private var loadedModelDir: URL?
    private var recognizer: (any DictationRecognizer)?
    private var loadedVADDir: URL?
    private var vad: SileroVADProcessor?
    private var loadedDiarDir: URL?
    private var diarizer: SpeakerDiarizer?

    func prepare(model: DictationModel, directory: URL) throws {
        if loadedModel == model, loadedModelDir == directory, recognizer != nil { return }
        recognizer = nil
        loadedModel = nil
        loadedModelDir = nil
        recognizer = try autoreleasepool { () throws -> any DictationRecognizer in
            switch model {
            case .qwenSmall, .qwenLarge:
                return try QwenRecognizer(directory: directory)
            case .ultra, .redux, .v2:
                return try ParakeetRecognizer(directory: directory, model: model)
            case .ctc, .ctcSmall:
                return try ParakeetCTCRecognizer(directory: directory)
            case .nemotron:
                return try NemotronRecognizer(directory: directory)
            case .speechAnalyzer:
                throw DictationInferenceError.incompatibleModel
            case .sravaani:
                return try SraVaaniRecognizer(directory: directory)
            case .whisperApex:
                return try WhisperApexRecognizer(directory: directory)
            case .indicFlex:
                return try IndicFlexRecognizer(directory: directory)
            }
        }
        loadedModel = model
        loadedModelDir = directory
    }

    func warmupIfNeeded() {
        recognizer?.warmupIfNeeded()
    }

    func transcribe(
        samples: [Float],
        request: DictationWire.Request
    ) throws -> TimedTranscript {
        let totalStart = CFAbsoluteTimeGetCurrent()
        try prepare(model: request.model, directory: request.directory)
        guard let recognizer else { throw DictationInferenceError.incompatibleModel }

        let vadStart = CFAbsoluteTimeGetCurrent()
        let speechSpans = detectSpeechSpans(
            samples: samples, useVAD: request.useVAD, vadDirectory: request.vadDirectory)
        let vadMs = (CFAbsoluteTimeGetCurrent() - vadStart) * 1000

        let asrStart = CFAbsoluteTimeGetCurrent()
        var combinedWords = [TranscriptWord]()
        var combinedTexts = [String]()

        if speechSpans.isEmpty {
            let timed = try recognizer.transcribeTimed(samples, language: request.language)
            combinedWords = timed.words
            if !timed.text.isEmpty { combinedTexts.append(timed.text) }
        } else {
            for span in speechSpans {
                let slice = Array(samples[span.startSample..<span.endSample])
                guard !slice.isEmpty else { continue }
                let timed = try recognizer.transcribeTimed(slice, language: request.language)
                let offset = Double(span.startSample) / Double(DictationWire.sampleRate)
                if !timed.text.isEmpty { combinedTexts.append(timed.text) }
                for word in timed.words {
                    combinedWords.append(TranscriptWord(
                        text: word.text,
                        start: word.start + offset,
                        end: word.end + offset,
                        confidence: word.confidence
                    ))
                }
            }
        }
        let asrMs = (CFAbsoluteTimeGetCurrent() - asrStart) * 1000

        let fullText = combinedTexts.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let diarStart = CFAbsoluteTimeGetCurrent()
        var turns = [SpeakerTurn]()
        if let speakerOption = request.diarizeSpeakers,
            let diarDir = request.diarizationDirectory,
            samples.count >= 8_000
        {
            if loadedDiarDir != diarDir || diarizer == nil {
                diarizer = try? SpeakerDiarizer(directory: diarDir)
                loadedDiarDir = diarDir
            }
            if let diarizer {
                let targetCount = speakerOption > 0 ? speakerOption : nil
                turns = (try? diarizer.diarize(
                    samples: samples, speakerCount: targetCount, labelPrefix: "Speaker")) ?? []
            }
        }
        let diarMs = (CFAbsoluteTimeGetCurrent() - diarStart) * 1000
        let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000

        let segments = TranscriptSegmentBuilder.build(
            words: combinedWords,
            turns: turns,
            fallbackText: fullText
        )
        let timings = DictationStageTimings(
            vadMs: vadMs,
            asrMs: asrMs,
            diarizationMs: diarMs,
            totalMs: totalMs
        )
        return TimedTranscript(text: fullText, words: combinedWords, segments: segments, timings: timings)
    }

    private func detectSpeechSpans(
        samples: [Float], useVAD: Bool, vadDirectory: URL?
    ) -> [DictationVADChunker.SpeechSpan] {
        // Apply Silero VAD down to 1.5s clips so leading/trailing silence and long pauses are stripped.
        guard useVAD, samples.count > 24_000 else { return [] }
        let rawSpans: [DictationVADChunker.SpeechSpan]
        if let vadDirectory {
            if loadedVADDir != vadDirectory || vad == nil {
                vad = try? SileroVADProcessor(directory: vadDirectory)
                loadedVADDir = vadDirectory
            }
            if let vad, let detected = try? vad.speechSpans(in: samples), !detected.isEmpty {
                rawSpans = detected
            } else {
                rawSpans = DictationVADChunker.energySpeechSpans(samples: samples)
            }
        } else {
            rawSpans = DictationVADChunker.energySpeechSpans(samples: samples)
        }
        guard !rawSpans.isEmpty else { return [] }
        // Merge spans closer than 1.8s so natural breaths keep decoder context.
        var coalesced = [rawSpans[0]]
        for span in rawSpans.dropFirst() {
            if span.startSample - coalesced[coalesced.count - 1].endSample <= 28_800 {
                coalesced[coalesced.count - 1].endSample = max(
                    coalesced[coalesced.count - 1].endSample, span.endSample)
            } else {
                coalesced.append(span)
            }
        }
        // Short-speech safety fallback: avoid over-trimming soft whispers <= 3s.
        let totalSpeechSamples = coalesced.reduce(0) { $0 + ($1.endSample - $1.startSample) }
        if totalSpeechSamples < 4_800, samples.count <= 48_000 {
            return []
        }
        return coalesced
    }
}
