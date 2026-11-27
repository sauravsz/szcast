import Accelerate
@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import CoreMedia
import os

/// Thread-safe reusable 16 kHz mono resampler box isolated behind an unfair lock.
private final class AudioTapResampler: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var scratch: AVAudioPCMBuffer?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func convertTo16kHzMono(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard buffer.frameLength > 0 else { return nil }
        let bufFormat = buffer.format
        if bufFormat.sampleRate == targetFormat.sampleRate,
           bufFormat.channelCount == 1,
           bufFormat.commonFormat == .pcmFormatFloat32,
           let src = buffer.floatChannelData?[0]
        {
            return Array(UnsafeBufferPointer(start: src, count: Int(buffer.frameLength)))
        }

        lock.lock()
        defer { lock.unlock() }
        if converter == nil || sourceFormat != bufFormat {
            converter = AVAudioConverter(from: bufFormat, to: targetFormat)
            sourceFormat = bufFormat
        }
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / max(1, bufFormat.sampleRate)
        let neededCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
        if scratch == nil || (scratch?.frameCapacity ?? 0) < neededCapacity {
            scratch = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(2048, neededCapacity))
        }
        guard let outBuffer = scratch else { return nil }
        outBuffer.frameLength = 0
        var error: NSError?
        var provided = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, outBuffer.frameLength > 0,
              let ch0 = outBuffer.floatChannelData?[0]
        else { return nil }
        return Array(UnsafeBufferPointer(start: ch0, count: Int(outBuffer.frameLength)))
    }
}

/// Fixed-capacity lock-free-friendly circular ring buffer for instant 350ms microphone pre-roll.
private final class PreRollRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let state: OSAllocatedUnfairLock<(storage: [Float], writeIndex: Int, filled: Int)>

    init(capacity: Int = 5_600) {
        self.capacity = max(1, capacity)
        self.state = OSAllocatedUnfairLock(
            initialState: (storage: [Float](repeating: 0, count: max(1, capacity)), writeIndex: 0, filled: 0))
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        state.withLock { s in
            if samples.count >= capacity {
                let start = samples.count - capacity
                for i in 0..<capacity { s.storage[i] = samples[start + i] }
                s.writeIndex = 0
                s.filled = capacity
                return
            }
            let firstPart = min(samples.count, capacity - s.writeIndex)
            for i in 0..<firstPart { s.storage[s.writeIndex + i] = samples[i] }
            let remaining = samples.count - firstPart
            if remaining > 0 {
                for i in 0..<remaining { s.storage[i] = samples[firstPart + i] }
            }
            s.writeIndex = (s.writeIndex + samples.count) % capacity
            s.filled = min(capacity, s.filled + samples.count)
        }
    }

    func drain() -> [Float] {
        state.withLock { s in
            guard s.filled > 0 else { return [] }
            var out = [Float](repeating: 0, count: s.filled)
            if s.filled < capacity {
                out.replaceSubrange(0..<s.filled, with: s.storage[0..<s.filled])
            } else {
                let tailCount = capacity - s.writeIndex
                for i in 0..<tailCount { out[i] = s.storage[s.writeIndex + i] }
                for i in 0..<s.writeIndex { out[tailCount + i] = s.storage[i] }
            }
            s.writeIndex = 0
            s.filled = 0
            return out
        }
    }

    func clear() {
        state.withLock { s in
            s.writeIndex = 0
            s.filled = 0
        }
    }
}

@MainActor
final class DictationCapture {
    enum Failure: LocalizedError {
        case microphoneUnavailable
        case microphoneDenied
        case captureUnavailable

        var errorDescription: String? {
            switch self {
            case .microphoneUnavailable: String(localized: "No microphone is available.")
            case .microphoneDenied:
                String(localized: "Allow szcast to use the microphone in System Settings.")
            case .captureUnavailable: String(localized: "Couldn't start recording from this microphone.")
            }
        }
    }

    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationCapture")

    static var microphones: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
    }

    static func isClamshellModeActive() -> Bool {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let hasBuiltin = displays.contains { CGDisplayIsBuiltin($0) != 0 }
        let hasExternal = displays.contains { CGDisplayIsBuiltin($0) == 0 }
        return !hasBuiltin && hasExternal
    }

    static func isBuiltInMicrophone(_ device: AVCaptureDevice) -> Bool {
        if UInt32(bitPattern: device.transportType) == UInt32(kAudioDeviceTransportTypeBuiltIn) { return true }
        let lower = device.localizedName.lowercased()
        return lower.contains("macbook") || lower.contains("built-in") || lower.contains("internal")
    }

    /// Resolves microphone priority: explicit device -> priority fallback list -> external mic in clamshell -> default.
    static func resolveDevice(
        microphoneID: String?,
        prioritizedIDs: [String] = [],
        isClamshell: Bool = isClamshellModeActive()
    ) -> AVCaptureDevice? {
        let available = microphones
        if let id = microphoneID, !id.isEmpty,
           let match = available.first(where: { $0.uniqueID == id }) {
            return match
        }
        for candidateID in prioritizedIDs where !candidateID.isEmpty {
            if let match = available.first(where: { $0.uniqueID == candidateID }) {
                return match
            }
        }
        if isClamshell, let externalMic = available.first(where: { !isBuiltInMicrophone($0) }) {
            return externalMic
        }
        return AVCaptureDevice.default(for: .audio) ?? available.first
    }

    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
            size > 0
        else { return nil }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr
        else { return nil }

        for id in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfUID: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &cfUID) == noErr,
               let resolvedUID = cfUID?.takeRetainedValue() as String?,
               resolvedUID == uid {
                return id
            }
        }
        return nil
    }

    var onLevels: (([Float]) -> Void)?
    var onLimit: (() -> Void)?
    var onSamples: (@Sendable ([Float]) -> Void)?
    var onPauseChunk: (@Sendable (_ rangeEndSample: Int, _ chunk: [Float]) -> Void)?
    var onSilenceWarning: ((Bool) -> Void)?
    var onClippingWarning: ((Bool) -> Void)?
    var onClamshellWarning: ((Bool) -> Void)?
    var onAutoStopSilence: (() -> Void)?
    var isWhisperMode = false
    private(set) var isMuted = false

    private(set) var isBluetooth = false
    private(set) var isClamshellMuffled = false
    private var session: AVCaptureSession?
    private var output: AVCaptureAudioDataOutput?
    private var audioEngine: AVAudioEngine?
    private var collector: AudioCollector?
    private var sessionStartTask: Task<Void, Never>?
    private var sessionStopTask: Task<Void, Never>?
    private var warmPreRollActive = false
    private var warmPreRollDeviceUID: String?
    private var warmPreRollVoiceProcessing = false
    private static let sessionStartTimeoutSeconds: Double = 4.0

    func setMuted(_ muted: Bool) {
        isMuted = muted
        collector?.setMuted(muted)
    }

    /// Arms or disarms an always-warm 350ms ring buffer using AVAudioEngine when opted in.
    func configureWarmPreRoll(enabled: Bool, microphoneID: String?, voiceProcessing: Bool = false) {
        guard enabled else {
            warmPreRollActive = false
            warmPreRollDeviceUID = nil
            if session == nil { stopWarmEngineIfNeeded() }
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        let device = Self.resolveDevice(microphoneID: microphoneID)
        let uid = device?.uniqueID
        if warmPreRollActive, audioEngine?.isRunning == true,
           warmPreRollDeviceUID == uid, warmPreRollVoiceProcessing == voiceProcessing {
            return
        }
        warmPreRollActive = true
        warmPreRollDeviceUID = uid
        warmPreRollVoiceProcessing = voiceProcessing
        guard session == nil, audioEngine == nil else { return }
        Task { [weak self] in
            guard let self, warmPreRollActive, session == nil, audioEngine == nil, let device else { return }
            try? await startWarmPreRollEngine(device: device, voiceProcessing: voiceProcessing)
        }
    }

    private func startWarmPreRollEngine(device: AVCaptureDevice, voiceProcessing: Bool) async throws {
        let isBT = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE]
            .contains(UInt32(bitPattern: device.transportType))
        let preCollector = try AudioCollector(
            preRollOnly: true,
            onLevels: { _ in },
            onLimit: {}
        )
        let engine = try buildAudioEngine(device: device, isBluetooth: isBT, voiceProcessing: voiceProcessing, collector: preCollector)
        let box = AudioEngineBox(engine)
        let started = await Self.awaitWithin(seconds: Self.sessionStartTimeoutSeconds) {
            try? box.engine.start()
        }
        guard started, warmPreRollActive, session == nil, audioEngine == nil, engine.isRunning else {
            box.engine.inputNode.removeTap(onBus: 0)
            box.engine.stop()
            return
        }
        self.audioEngine = engine
        self.collector = preCollector
    }

    private func stopWarmEngineIfNeeded() {
        guard let engine = audioEngine, session == nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        self.audioEngine = nil
        self.collector = nil
        let box = AudioEngineBox(engine)
        let previousStop = sessionStopTask
        sessionStopTask = Task.detached(priority: .utility) {
            await previousStop?.value
            box.engine.stop()
        }
    }

    func start(
        microphoneID: String?,
        prioritizedMicrophoneIDs: [String] = [],
        whisperMode: Bool = false,
        allowLongCapture: Bool = false,
        startMuted: Bool = false,
        autoStopSilenceSeconds: TimeInterval = 0,
        voiceProcessing: Bool = false
    ) async throws {
        isMuted = startMuted
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        let granted: Bool
        if permission == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            granted = permission == .authorized
        }
        guard granted else { throw Failure.microphoneDenied }

        let isClamshell = Self.isClamshellModeActive()
        guard let device = Self.resolveDevice(
            microphoneID: microphoneID,
            prioritizedIDs: prioritizedMicrophoneIDs,
            isClamshell: isClamshell
        ) else {
            throw Failure.microphoneUnavailable
        }

        if isClamshell && Self.isBuiltInMicrophone(device) {
            isClamshellMuffled = true
            onClamshellWarning?(true)
        } else {
            isClamshellMuffled = false
            onClamshellWarning?(false)
        }

        isBluetooth = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE]
            .contains(UInt32(bitPattern: device.transportType))

        let samplesHandler = self.onSamples
        let pauseHandler = self.onPauseChunk
        let maxSamples = allowLongCapture
            ? DictationWire.sampleRate * 3_600 * 6
            : DictationWire.maximumSamples
        let autoStopSamples = autoStopSilenceSeconds > 0
            ? Int(autoStopSilenceSeconds * Double(DictationWire.sampleRate)) : 0

        // Fast path 1: Warm Pre-Roll promotion (<2ms, includes trailing 350ms spoken before trigger!).
        if warmPreRollActive,
           let engine = audioEngine, engine.isRunning,
           let existingCollector = collector,
           warmPreRollDeviceUID == device.uniqueID
        {
            existingCollector.promoteFromPreRoll(
                whisperMode: whisperMode,
                maximumSamples: maxSamples,
                startMuted: startMuted,
                autoStopSilenceSamples: autoStopSamples,
                onLevels: { [weak self] levels in
                    Task { @MainActor [weak self] in self?.onLevels?(levels) }
                },
                onLimit: { [weak self] in
                    Task { @MainActor [weak self] in self?.onLimit?() }
                },
                onSamples: { chunk in samplesHandler?(chunk) },
                onPauseChunk: { endIdx, chunk in pauseHandler?(endIdx, chunk) },
                onSilenceWarning: { [weak self] silent in
                    Task { @MainActor [weak self] in self?.onSilenceWarning?(silent) }
                },
                onClippingWarning: { [weak self] clipping in
                    Task { @MainActor [weak self] in self?.onClippingWarning?(clipping) }
                },
                onAutoStopSilence: { [weak self] in
                    Task { @MainActor [weak self] in self?.onAutoStopSilence?() }
                }
            )
            Self.logger.debug("DictationCapture promoted warm pre-roll engine in <2ms")
            return
        }

        // Stop any mismatched warm engine before starting fresh.
        stopWarmEngineIfNeeded()

        let collector = try AudioCollector(
            preRollOnly: false,
            whisperMode: whisperMode,
            maximumSamples: maxSamples,
            startMuted: startMuted,
            autoStopSilenceSamples: autoStopSamples,
            onLevels: { [weak self] levels in
                Task { @MainActor [weak self] in self?.onLevels?(levels) }
            },
            onLimit: { [weak self] in
                Task { @MainActor [weak self] in self?.onLimit?() }
            },
            onSamples: { chunk in samplesHandler?(chunk) },
            onPauseChunk: { endIdx, chunk in pauseHandler?(endIdx, chunk) },
            onSilenceWarning: { [weak self] silent in
                Task { @MainActor [weak self] in self?.onSilenceWarning?(silent) }
            },
            onClippingWarning: { [weak self] clipping in
                Task { @MainActor [weak self] in self?.onClippingWarning?(clipping) }
            },
            onAutoStopSilence: { [weak self] in
                Task { @MainActor [weak self] in self?.onAutoStopSilence?() }
            })

        if let pendingStop = sessionStopTask {
            let drained = await Self.awaitWithin(seconds: Self.sessionStartTimeoutSeconds) {
                await pendingStop.value
            }
            if drained { sessionStopTask = nil }
        }

        // Fast path 2: Low-latency AVAudioEngine with CoreAudio device binding & Voice Processing.
        if let engine = try? buildAudioEngine(
            device: device,
            isBluetooth: isBluetooth,
            voiceProcessing: voiceProcessing,
            collector: collector
        ) {
            self.audioEngine = engine
            self.collector = collector
            let box = AudioEngineBox(engine)
            let startTask = Task.detached { _ = try? box.engine.start() }
            sessionStartTask = startTask
            let started = await Self.awaitWithin(seconds: Self.sessionStartTimeoutSeconds) {
                await startTask.value
            }
            if started { sessionStartTask = nil }
            if started, self.audioEngine === engine, engine.isRunning {
                return
            }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.audioEngine = nil
            self.collector = nil
        }

        // Fallback path: AVCaptureSession (handles exotic aggregate/virtual drivers gracefully).
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw Failure.captureUnavailable
        }

        let capture = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: DictationWire.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        guard capture.canAddInput(input), capture.canAddOutput(output) else {
            throw Failure.captureUnavailable
        }
        capture.addInput(input)
        capture.addOutput(output)
        output.setSampleBufferDelegate(collector, queue: collector.queue)
        self.session = capture
        self.output = output
        self.collector = collector

        let box = CaptureSessionBox(capture)
        let startTask = Task.detached { box.session.startRunning() }
        sessionStartTask = startTask
        let started = await Self.awaitWithin(seconds: Self.sessionStartTimeoutSeconds) {
            await startTask.value
        }
        if started { sessionStartTask = nil }
        guard started, self.session === capture, capture.isRunning else {
            _ = await stop()
            throw Failure.captureUnavailable
        }
    }

    private func buildAudioEngine(
        device: AVCaptureDevice,
        isBluetooth: Bool,
        voiceProcessing: Bool,
        collector: AudioCollector
    ) throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if let au = inputNode.audioUnit, var devID = Self.audioDeviceID(forUID: device.uniqueID) {
            let status = AudioUnitSetProperty(
                au,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                Self.logger.debug("AudioUnit device binding returned status \(status); using AVAudioEngine default route")
            }
        }

        if voiceProcessing, !isBluetooth {
            try? inputNode.setVoiceProcessingEnabled(true)
        }

        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Double(DictationWire.sampleRate),
                  channels: 1,
                  interleaved: false
              )
        else {
            throw Failure.captureUnavailable
        }

        let resampler = AudioTapResampler(targetFormat: targetFormat)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [collector, resampler] buffer, _ in
            if let outSamples = resampler.convertTo16kHzMono(buffer), !outSamples.isEmpty {
                collector.enqueuePCM16kHz(outSamples)
            }
        }
        engine.prepare()
        return engine
    }

    func stop() async -> [Float] {
        // Warm pre-roll engine keeps running cleanly by demoting back to pre-roll ring buffer.
        if let engine = audioEngine {
            if warmPreRollActive {
                let samples = collector?.demoteToPreRoll() ?? []
                return samples
            }
            self.audioEngine = nil
            engine.inputNode.removeTap(onBus: 0)
            let samples = collector?.finish() ?? []
            collector = nil
            let box = AudioEngineBox(engine)
            let previousStart = sessionStartTask
            sessionStartTask = nil
            let previousStop = sessionStopTask
            sessionStopTask = Task.detached(priority: .utility) {
                await previousStop?.value
                await previousStart?.value
                box.engine.stop()
            }
            return samples
        }

        guard let session else { return [] }
        self.session = nil
        output?.setSampleBufferDelegate(nil, queue: nil)
        output = nil
        let samples = collector?.finish() ?? []
        collector = nil
        let box = CaptureSessionBox(session)
        let previousStart = sessionStartTask
        sessionStartTask = nil
        let previousStop = sessionStopTask
        sessionStopTask = Task.detached(priority: .utility) {
            await previousStop?.value
            await previousStart?.value
            box.session.stopRunning()
        }
        return samples
    }

    private static func awaitWithin(
        seconds: Double,
        operation: @escaping @Sendable () async -> Void
    ) async -> Bool {
        let settled = OSAllocatedUnfairLock(initialState: false)
        return await withCheckedContinuation { continuation in
            Task.detached {
                await operation()
                if settled.withLock({ let was = $0; $0 = true; return !was }) {
                    continuation.resume(returning: true)
                }
            }
            Task.detached {
                try? await Task.sleep(for: .seconds(seconds))
                if settled.withLock({ let was = $0; $0 = true; return !was }) {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func snapshot() -> [Float] {
        guard session != nil || audioEngine != nil else { return [] }
        return collector?.snapshot() ?? []
    }
}

private struct AudioEngineBox: @unchecked Sendable {
    let engine: AVAudioEngine
    init(_ engine: AVAudioEngine) { self.engine = engine }
}

// Configuration stays on main; only start/stop run off-main, in sequence.
private struct CaptureSessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}

// Sample buffers and mutable state are confined to the delegate queue, including finish().
private final class AudioCollector: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    let queue = DispatchQueue(label: "com.sauravsz.szcast.dictation.audio")
    private var samples: [Float] = []
    private var displayedLevels: [Float]
    private let spectrum: DictationSpectrum
    private let preRollRing = PreRollRingBuffer(capacity: 5_600)
    private var preRollOnly: Bool
    private var waveformStartIndex = 0
    private var lastLevelUpdate: TimeInterval = 0
    private var reachedLimit = false
    private var whisperMode: Bool
    private var silentSamples = 0
    private var silenceReported = false
    private var clippingStreak = 0
    private var nonClippingSamples = 0
    private var clippingReported = false
    private var lastPauseEmittedIndex = 0
    private var activeSpeechSinceEmitSamples = 0
    private var trailingPauseSamples = 0
    private var maximumSamples: Int
    private var muted: Bool
    private var autoStopSilenceSamples: Int
    private var trailingSilentSamples = 0
    private var autoStopTriggered = false
    private var heardAnySpeech = false
    private var onLevels: @Sendable ([Float]) -> Void
    private var onLimit: @Sendable () -> Void
    private var onSamples: (@Sendable ([Float]) -> Void)?
    private var onPauseChunk: (@Sendable (_ rangeEndSample: Int, _ chunk: [Float]) -> Void)?
    private var onSilenceWarning: (@Sendable (Bool) -> Void)?
    private var onClippingWarning: (@Sendable (Bool) -> Void)?
    private var onAutoStopSilence: (@Sendable () -> Void)?

    init(
        preRollOnly: Bool = false,
        whisperMode: Bool = false,
        maximumSamples: Int = DictationWire.maximumSamples,
        startMuted: Bool = false,
        autoStopSilenceSamples: Int = 0,
        onLevels: @escaping @Sendable ([Float]) -> Void,
        onLimit: @escaping @Sendable () -> Void,
        onSamples: (@Sendable ([Float]) -> Void)? = nil,
        onPauseChunk: (@Sendable (_ rangeEndSample: Int, _ chunk: [Float]) -> Void)? = nil,
        onSilenceWarning: (@Sendable (Bool) -> Void)? = nil,
        onClippingWarning: (@Sendable (Bool) -> Void)? = nil,
        onAutoStopSilence: (@Sendable () -> Void)? = nil
    ) throws {
        self.preRollOnly = preRollOnly
        self.whisperMode = whisperMode
        self.maximumSamples = maximumSamples
        self.muted = startMuted
        self.autoStopSilenceSamples = autoStopSilenceSamples
        spectrum = try DictationSpectrum()
        displayedLevels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        self.onLevels = onLevels
        self.onLimit = onLimit
        self.onSamples = onSamples
        self.onPauseChunk = onPauseChunk
        self.onSilenceWarning = onSilenceWarning
        self.onClippingWarning = onClippingWarning
        self.onAutoStopSilence = onAutoStopSilence
    }

    func setMuted(_ isMuted: Bool) {
        queue.async { self.muted = isMuted }
    }

    func promoteFromPreRoll(
        whisperMode: Bool,
        maximumSamples: Int,
        startMuted: Bool,
        autoStopSilenceSamples: Int,
        onLevels: @escaping @Sendable ([Float]) -> Void,
        onLimit: @escaping @Sendable () -> Void,
        onSamples: (@Sendable ([Float]) -> Void)?,
        onPauseChunk: (@Sendable (_ rangeEndSample: Int, _ chunk: [Float]) -> Void)?,
        onSilenceWarning: (@Sendable (Bool) -> Void)?,
        onClippingWarning: (@Sendable (Bool) -> Void)?,
        onAutoStopSilence: (@Sendable () -> Void)?
    ) {
        queue.sync {
            let prefix = startMuted ? [] : preRollRing.drain()
            self.samples = prefix
            self.waveformStartIndex = prefix.count
            self.lastLevelUpdate = 0
            self.reachedLimit = false
            self.whisperMode = whisperMode
            self.maximumSamples = maximumSamples
            self.muted = startMuted
            self.autoStopSilenceSamples = autoStopSilenceSamples
            self.silentSamples = 0
            self.silenceReported = false
            self.clippingStreak = 0
            self.nonClippingSamples = 0
            self.clippingReported = false
            self.lastPauseEmittedIndex = 0
            self.activeSpeechSinceEmitSamples = 0
            self.trailingPauseSamples = 0
            self.trailingSilentSamples = 0
            self.autoStopTriggered = false
            self.heardAnySpeech = false
            self.onLevels = onLevels
            self.onLimit = onLimit
            self.onSamples = onSamples
            self.onPauseChunk = onPauseChunk
            self.onSilenceWarning = onSilenceWarning
            self.onClippingWarning = onClippingWarning
            self.onAutoStopSilence = onAutoStopSilence
            self.preRollOnly = false
        }
    }

    func demoteToPreRoll() -> [Float] {
        queue.sync {
            let out = samples
            samples.removeAll(keepingCapacity: true)
            preRollRing.clear()
            preRollOnly = true
            onLevels = { _ in }
            onLimit = {}
            onSamples = nil
            onPauseChunk = nil
            onSilenceWarning = nil
            onClippingWarning = nil
            onAutoStopSilence = nil
            return out
        }
    }

    func enqueuePCM16kHz(_ incoming: [Float]) {
        queue.async { [weak self] in
            self?.processIncoming(incoming)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        var blockBuffer: CMBlockBuffer?
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let data = bufferList.mBuffers.mData else { return }
        let count = Int(bufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return }
        let floats = data.assumingMemoryBound(to: Float.self)
        let incoming = Array(UnsafeBufferPointer(start: floats, count: count))
        processIncoming(incoming)
    }

    private func processIncoming(_ incoming: [Float]) {
        if preRollOnly {
            preRollRing.append(incoming)
            return
        }
        guard !incoming.isEmpty, samples.count < maximumSamples else { return }
        let accepted = min(incoming.count, maximumSamples - samples.count)
        var chunk: [Float]
        if muted {
            chunk = [Float](repeating: 0, count: accepted)
        } else {
            chunk = accepted == incoming.count ? incoming : Array(incoming.prefix(accepted))
            if whisperMode {
                for i in 0..<chunk.count {
                    let sample = chunk[i] * 3.2
                    chunk[i] = sample / (1.0 + abs(sample) * 0.2)
                }
            }
        }
        samples.append(contentsOf: chunk)
        onSamples?(chunk)

        var chunkRms: Float = 0
        var chunkPeak: Float = 0
        vDSP_rmsqv(chunk, 1, &chunkRms, vDSP_Length(chunk.count))
        vDSP_maxmgv(chunk, 1, &chunkPeak, vDSP_Length(chunk.count))
        if chunkRms >= 0.003 { heardAnySpeech = true }

        // Clipping detector: warn if >= 4 blocks peak near full scale.
        if !muted && chunkPeak >= 0.992 {
            clippingStreak += 1
            nonClippingSamples = 0
            if clippingStreak >= 4, !clippingReported {
                clippingReported = true
                onClippingWarning?(true)
            }
        } else {
            nonClippingSamples += chunk.count
            if clippingReported, nonClippingSamples >= 24_000 {
                clippingReported = false
                clippingStreak = 0
                onClippingWarning?(false)
            }
        }

        if muted {
            silentSamples = 0
            if silenceReported {
                silenceReported = false
                onSilenceWarning?(false)
            }
        } else {
            let threshold: Float = heardAnySpeech ? 0.0003 : 0.0012
            let requiredSamples = heardAnySpeech ? 48_000 : 24_000
            if chunkRms < threshold {
                silentSamples += chunk.count
                if silentSamples >= requiredSamples, !silenceReported {
                    silenceReported = true
                    onSilenceWarning?(true)
                }
            } else {
                silentSamples = 0
                if silenceReported, chunkRms > 0.003 {
                    silenceReported = false
                    onSilenceWarning?(false)
                }
            }
        }

        // Speculative pause chunking: emit quiet-cut slice when >= 2.0s speech precedes >= 400ms pause.
        if !muted, onPauseChunk != nil {
            if chunkRms < 0.002 {
                trailingPauseSamples += chunk.count
                if activeSpeechSinceEmitSamples >= 32_000, trailingPauseSamples >= 6_400 {
                    let cutIndex = DictationAudioChunks.liveCut(
                        in: samples, from: lastPauseEmittedIndex, to: samples.count)
                    if cutIndex - lastPauseEmittedIndex >= 24_000 {
                        let slice = Array(samples[lastPauseEmittedIndex..<cutIndex])
                        lastPauseEmittedIndex = cutIndex
                        activeSpeechSinceEmitSamples = 0
                        trailingPauseSamples = 0
                        onPauseChunk?(cutIndex, slice)
                    }
                }
            } else if chunkRms >= 0.006 {
                activeSpeechSinceEmitSamples += chunk.count
                trailingPauseSamples = 0
            }
        }

        if autoStopSilenceSamples > 0, heardAnySpeech, !muted, !autoStopTriggered {
            if chunkRms < 0.0015 {
                trailingSilentSamples += chunk.count
                if trailingSilentSamples >= autoStopSilenceSamples {
                    autoStopTriggered = true
                    onAutoStopSilence?()
                }
            } else {
                trailingSilentSamples = 0
            }
        }

        if samples.count == maximumSamples, !reachedLimit {
            reachedLimit = true
            onLimit()
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelUpdate >= 0.05 else { return }
        lastLevelUpdate = now
        let levels = spectrum.levels(for: samples[waveformStartIndex...])
        waveformStartIndex = samples.count
        for index in levels.indices {
            let response: Float = levels[index] > displayedLevels[index] ? 0.6 : 0.25
            displayedLevels[index] += (levels[index] - displayedLevels[index]) * response
        }
        onLevels(displayedLevels)
    }

    func finish() -> [Float] {
        queue.sync {
            let out = samples
            samples.removeAll(keepingCapacity: false)
            return out
        }
    }

    func snapshot() -> [Float] { queue.sync { samples } }
}
