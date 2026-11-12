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
    private var isRunning = false
    private var committedText = ""
    private var inFlightText = ""

    func start(
        locale: Locale = .current,
        onText: @escaping @Sendable (String) -> Void
    ) async {
        stop()
        do {
            let installed = await DictationTranscriber.installedLocales
            let effectiveLocale = (await DictationTranscriber.supportedLocale(equivalentTo: locale))
                ?? installed.first
                ?? Locale(identifier: "en-US")

            let module = DictationTranscriber(locale: effectiveLocale, preset: .progressiveLongDictation)
            guard let source = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ) else { return }

            guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [module],
                considering: source
            ) else { return }

            sourceFormat = source
            targetFormat = target
            converter = (source == target) ? nil : AVAudioConverter(from: source, to: target)

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(
                bufferingPolicy: .bufferingNewest(50)
            )
            let analyzer = SpeechAnalyzer(modules: [module])
            try await analyzer.prepareToAnalyze(in: target)
            try await analyzer.start(inputSequence: stream)

            self.analyzer = analyzer
            self.streamContinuation = continuation
            self.committedText = ""
            self.inFlightText = ""
            self.isRunning = true

            self.collectorTask = Task { [weak self] in
                do {
                    for try await result in module.results {
                        guard let self else { break }
                        let text = String(result.text.characters)
                        let isFinal = result.isFinal
                        let current = await self.updateText(piece: text, isFinal: isFinal)
                        onText(current)
                    }
                } catch {
                    // Preview stream ended or cancelled
                }
            }
        } catch {
            self.analyzer = nil
            self.streamContinuation = nil
            self.isRunning = false
        }
    }

    private func updateText(piece: String, isFinal: Bool) -> String {
        if isFinal {
            committedText += piece
            inFlightText = ""
        } else {
            inFlightText = piece
        }
        return (committedText + inFlightText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func feed(_ samples: [Float]) {
        guard isRunning, let continuation = streamContinuation, let source = sourceFormat, let target = targetFormat,
              !samples.isEmpty,
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
        guard isRunning else { return }
        isRunning = false
        collectorTask?.cancel()
        collectorTask = nil
        streamContinuation?.finish()
        streamContinuation = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        converter = nil
    }
}

/// Coordinator bridging audio recording with the live preview recognizer.
final class DictationLivePreviewCoordinator: @unchecked Sendable {
    private var liveRecognizer: Any?
    var onPreviewText: (@Sendable (String) -> Void)?

    func start(locale: Locale = .current) {
        if #available(macOS 26.0, *) {
            let recognizer = DictationLivePreviewRecognizer()
            self.liveRecognizer = recognizer
            Task { [weak self] in
                await recognizer.start(locale: locale) { [weak self] text in
                    self?.onPreviewText?(text)
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
        liveRecognizer = nil
    }
}
