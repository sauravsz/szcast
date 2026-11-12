import AVFoundation
import Foundation
import Speech

/// On-device real-time speech preview recognizer for the floating dictation pill.
/// Runs in parallel with audio recording to provide live visual feedback of what the user is saying.
/// Used for DISPLAY ONLY in the pill — final transcription and polishing are handled by Parakeet + S1.
@available(macOS 26.0, *)
actor DictationLivePreviewRecognizer {
    private var analyzer: SpeechAnalyzer?
    private var streamContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var collectorTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?
    private var cachedEffectiveLocale: Locale?
    private var isSessionActive = false
    private var committedText = ""
    private var inFlightText = ""

    // Universal fallback via SFSpeechRecognizer
    private var sfRecognizer: SFSpeechRecognizer?
    private var sfRequest: SFSpeechAudioBufferRecognitionRequest?
    private var sfTask: SFSpeechRecognitionTask?

    init() {
        sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )
    }

    func prewarm(locale: Locale = .current) async {
        guard targetFormat == nil else { return }
        guard let source = sourceFormat else { return }
        let effectiveLocale = await resolveEffectiveLocale(locale)
        self.cachedEffectiveLocale = effectiveLocale
        let probe = DictationTranscriber(locale: effectiveLocale, preset: .progressiveLongDictation)
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [probe],
            considering: source
        ) else { return }
        self.targetFormat = target
        self.converter = (source == target) ? nil : AVAudioConverter(from: source, to: target)

        let warmAnalyzer = SpeechAnalyzer(modules: [probe])
        try? await warmAnalyzer.prepareToAnalyze(in: target)
        await warmAnalyzer.cancelAndFinishNow()
    }

    func start(
        locale: Locale = .current,
        onText: @escaping @Sendable (String) -> Void
    ) async {
        stop()
        isSessionActive = true
        committedText = ""
        inFlightText = ""

        guard let source = sourceFormat else { return }
        do {
            let effectiveLocale: Locale
            if let cached = cachedEffectiveLocale {
                effectiveLocale = cached
            } else {
                effectiveLocale = await resolveEffectiveLocale(locale)
                cachedEffectiveLocale = effectiveLocale
            }

            let module = DictationTranscriber(locale: effectiveLocale, preset: .progressiveLongDictation)

            let target: AVAudioFormat
            if let cachedTarget = targetFormat {
                target = cachedTarget
            } else {
                guard let resolvedTarget = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [module],
                    considering: source
                ) else {
                    startSFSpeechFallback(locale: locale, onText: onText)
                    return
                }
                targetFormat = resolvedTarget
                converter = (source == resolvedTarget) ? nil : AVAudioConverter(from: source, to: resolvedTarget)
                target = resolvedTarget
            }

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(
                bufferingPolicy: .bufferingNewest(50)
            )
            self.streamContinuation = continuation

            let analyzer = SpeechAnalyzer(modules: [module])
            try await analyzer.prepareToAnalyze(in: target)
            guard isSessionActive else {
                await analyzer.cancelAndFinishNow()
                return
            }
            try await analyzer.start(inputSequence: stream)
            self.analyzer = analyzer

            self.collectorTask = Task { [weak self] in
                do {
                    for try await result in module.results {
                        guard let self, await self.isActive() else { break }
                        let text = String(result.text.characters)
                        let isFinal = result.isFinal
                        let current = await self.updateText(piece: text, isFinal: isFinal)
                        onText(current)
                    }
                } catch {
                    // Preview stream finished or cancelled
                }
            }
        } catch {
            self.analyzer = nil
            self.streamContinuation = nil
            startSFSpeechFallback(locale: locale, onText: onText)
        }
    }

    private func isActive() -> Bool {
        isSessionActive
    }

    private func resolveEffectiveLocale(_ locale: Locale) async -> Locale {
        let installed = await DictationTranscriber.installedLocales
        if installed.contains(where: { $0.identifier == locale.identifier }) {
            return locale
        } else if let match = installed.first(where: { $0.language.languageCode == locale.language.languageCode }) {
            return match
        } else if let first = installed.first {
            return first
        } else {
            return (await DictationTranscriber.supportedLocale(equivalentTo: locale))
                ?? Locale(identifier: "en-US")
        }
    }

    private func startSFSpeechFallback(
        locale: Locale,
        onText: @escaping @Sendable (String) -> Void
    ) {
        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            self.isSessionActive = false
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.sfRecognizer = recognizer
        self.sfRequest = request
        self.isSessionActive = true

        self.sfTask = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let transcription = result.bestTranscription.formattedString
                onText(transcription)
            }
        }
    }

    private static func join(_ a: String, _ b: String) -> String {
        let aTrim = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let bTrim = b.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !aTrim.isEmpty else { return bTrim }
        guard !bTrim.isEmpty else { return aTrim }
        guard let last = aTrim.last, let first = bTrim.first else { return aTrim + bTrim }
        if last.isWhitespace || first.isWhitespace { return aTrim + bTrim }
        if first == "." || first == "," || first == "!" || first == "?" || first == ":" || first == ";" {
            return aTrim + bTrim
        }
        return aTrim + " " + bTrim
    }

    private func updateText(piece: String, isFinal: Bool) -> String {
        if isFinal {
            committedText = Self.join(committedText, piece)
            inFlightText = ""
        } else {
            inFlightText = piece
        }
        let full = Self.join(committedText, inFlightText)
        return Self.applyBound(full)
    }

    private static func applyBound(_ text: String) -> String {
        guard text.count > 2000 else { return text }
        let tail = String(text.suffix(2000))
        guard let space = tail.firstIndex(of: " ") else { return tail }
        return String(tail[tail.index(after: space)...])
    }

    func feed(_ samples: [Float]) {
        guard isSessionActive, !samples.isEmpty else { return }

        // SFSpeechRecognizer fallback feeding
        if let sfRequest, let source = sourceFormat,
           let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
           let channel = buffer.floatChannelData {
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                channel[0].update(from: base, count: samples.count)
            }
            sfRequest.append(buffer)
            return
        }

        // SpeechAnalyzer feeding
        guard let continuation = streamContinuation, let source = sourceFormat, let target = targetFormat,
              let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            channel[0].update(from: base, count: samples.count)
        }

        let bufferToSend: AVAudioPCMBuffer
        if let converter {
            let ratio = target.sampleRate / source.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 512)
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            nonisolated(unsafe) let inBuf = buffer
            converter.convert(to: outBuffer, error: &error) { _, outStatus in
                if supplied {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                outStatus.pointee = .haveData
                return inBuf
            }
            guard error == nil, outBuffer.frameLength > 0 else { return }
            bufferToSend = outBuffer
        } else {
            bufferToSend = buffer
        }

        nonisolated(unsafe) let finalBuf = bufferToSend
        continuation.yield(AnalyzerInput(buffer: finalBuf))
    }

    func stop() {
        guard isSessionActive else { return }
        isSessionActive = false
        sfTask?.cancel()
        sfTask = nil
        sfRequest?.endAudio()
        sfRequest = nil
        sfRecognizer = nil
        collectorTask?.cancel()
        collectorTask = nil
        streamContinuation?.finish()
        streamContinuation = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
    }
}

/// Coordinator bridging audio recording with the live preview recognizer.
final class DictationLivePreviewCoordinator: @unchecked Sendable {
    private var liveRecognizer: Any?
    var onPreviewText: (@Sendable (String) -> Void)?

    init() {
        if #available(macOS 26.0, *) {
            self.liveRecognizer = DictationLivePreviewRecognizer()
        }
    }

    func prewarm(locale: Locale = .current) {
        if #available(macOS 26.0, *) {
            if let recognizer = liveRecognizer as? DictationLivePreviewRecognizer {
                Task {
                    await recognizer.prewarm(locale: locale)
                }
            }
        }
    }

    func start(locale: Locale = .current) {
        if #available(macOS 26.0, *) {
            if let recognizer = liveRecognizer as? DictationLivePreviewRecognizer {
                Task { [weak self] in
                    await recognizer.start(locale: locale) { [weak self] text in
                        self?.onPreviewText?(text)
                    }
                }
            }
        }
    }

    func feed(_ samples: [Float]) {
        if #available(macOS 26.0, *) {
            if let recognizer = liveRecognizer as? DictationLivePreviewRecognizer {
                Task {
                    await recognizer.feed(samples)
                }
            }
        }
    }

    func stop() {
        if #available(macOS 26.0, *) {
            if let recognizer = liveRecognizer as? DictationLivePreviewRecognizer {
                Task {
                    await recognizer.stop()
                }
            }
        }
    }
}
