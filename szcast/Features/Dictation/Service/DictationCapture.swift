import AVFoundation
import AudioToolbox
import CoreMedia
import os

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

    var onLevels: (([Float]) -> Void)?
    var onLimit: (() -> Void)?
    var onSamples: (@Sendable ([Float]) -> Void)?
    var onSilenceWarning: ((Bool) -> Void)?
    var onClamshellWarning: ((Bool) -> Void)?
    var onAutoStopSilence: (() -> Void)?
    var isWhisperMode = false
    private(set) var isMuted = false

    private(set) var isBluetooth = false
    private(set) var isClamshellMuffled = false
    private var session: AVCaptureSession?
    private var output: AVCaptureAudioDataOutput?
    private var collector: AudioCollector?
    private var sessionStartTask: Task<Void, Never>?
    private var sessionStopTask: Task<Void, Never>?
    private static let sessionStartTimeoutSeconds: Double = 4.0

    func setMuted(_ muted: Bool) {
        isMuted = muted
        collector?.setMuted(muted)
    }

    func start(
        microphoneID: String?,
        whisperMode: Bool = false,
        allowLongCapture: Bool = false,
        startMuted: Bool = false,
        autoStopSilenceSeconds: TimeInterval = 0
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
        let device: AVCaptureDevice?
        if microphoneID == nil && isClamshell,
           let externalMic = Self.microphones.first(where: { !Self.isBuiltInMicrophone($0) }) {
            // Auto-switch to external mic in clamshell mode
            device = externalMic
        } else {
            device =
                microphoneID.map { id in Self.microphones.first { $0.uniqueID == id } }
                ?? AVCaptureDevice.default(for: .audio)
        }
        guard let device else { throw Failure.microphoneUnavailable }

        if isClamshell && Self.isBuiltInMicrophone(device) {
            isClamshellMuffled = true
            onClamshellWarning?(true)
        } else {
            isClamshellMuffled = false
            onClamshellWarning?(false)
        }

        isBluetooth = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE]
            .contains(UInt32(bitPattern: device.transportType))
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
        let samplesHandler = self.onSamples
        let maxSamples = allowLongCapture
            ? DictationWire.sampleRate * 3_600 * 6
            : DictationWire.maximumSamples
        let collector = try AudioCollector(
            whisperMode: whisperMode,
            maximumSamples: maxSamples,
            startMuted: startMuted,
            autoStopSilenceSamples: autoStopSilenceSeconds > 0
                ? Int(autoStopSilenceSeconds * Double(DictationWire.sampleRate)) : 0,
            onLevels: { [weak self] levels in
                Task { @MainActor [weak self] in self?.onLevels?(levels) }
            },
            onLimit: { [weak self] in
                Task { @MainActor [weak self] in self?.onLimit?() }
            },
            onSamples: { chunk in
                samplesHandler?(chunk)
            },
            onSilenceWarning: { [weak self] silent in
                Task { @MainActor [weak self] in self?.onSilenceWarning?(silent) }
            },
            onAutoStopSilence: { [weak self] in
                Task { @MainActor [weak self] in self?.onAutoStopSilence?() }
            })
        output.setSampleBufferDelegate(collector, queue: collector.queue)
        self.session = capture
        self.output = output
        self.collector = collector
        if let pendingStop = sessionStopTask {
            let drained = await Self.awaitWithin(seconds: Self.sessionStartTimeoutSeconds) {
                await pendingStop.value
            }
            if drained { sessionStopTask = nil }
        }
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

    func stop() async -> [Float] {
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
        guard session != nil else { return [] }
        return collector?.snapshot() ?? []
    }
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
    private var waveformStartIndex = 0
    private var lastLevelUpdate: TimeInterval = 0
    private var reachedLimit = false
    private let whisperMode: Bool
    private var silentSamples = 0
    private var silenceReported = false
    private let maximumSamples: Int
    private var muted: Bool
    private let autoStopSilenceSamples: Int
    private var trailingSilentSamples = 0
    private var autoStopTriggered = false
    private var heardAnySpeech = false
    private let onLevels: @Sendable ([Float]) -> Void
    private let onLimit: @Sendable () -> Void
    private let onSamples: (@Sendable ([Float]) -> Void)?
    private let onSilenceWarning: (@Sendable (Bool) -> Void)?
    private let onAutoStopSilence: (@Sendable () -> Void)?

    init(
        whisperMode: Bool = false,
        maximumSamples: Int = DictationWire.maximumSamples,
        startMuted: Bool = false,
        autoStopSilenceSamples: Int = 0,
        onLevels: @escaping @Sendable ([Float]) -> Void,
        onLimit: @escaping @Sendable () -> Void,
        onSamples: (@Sendable ([Float]) -> Void)? = nil,
        onSilenceWarning: (@Sendable (Bool) -> Void)? = nil,
        onAutoStopSilence: (@Sendable () -> Void)? = nil
    ) throws {
        self.whisperMode = whisperMode
        self.maximumSamples = maximumSamples
        self.muted = startMuted
        self.autoStopSilenceSamples = autoStopSilenceSamples
        spectrum = try DictationSpectrum()
        displayedLevels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        self.onLevels = onLevels
        self.onLimit = onLimit
        self.onSamples = onSamples
        self.onSilenceWarning = onSilenceWarning
        self.onAutoStopSilence = onAutoStopSilence
    }

    func setMuted(_ isMuted: Bool) {
        queue.async { self.muted = isMuted }
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
        guard count > 0, samples.count < maximumSamples else { return }
        let floats = data.assumingMemoryBound(to: Float.self)
        let accepted = min(count, maximumSamples - samples.count)
        var chunk: [Float]
        if muted {
            chunk = [Float](repeating: 0, count: accepted)
        } else {
            chunk = Array(UnsafeBufferPointer(start: floats, count: accepted))
            if whisperMode {
                for i in 0..<chunk.count {
                    let sample = chunk[i] * 3.2
                    chunk[i] = sample / (1.0 + abs(sample) * 0.2)
                }
            }
        }
        samples.append(contentsOf: chunk)
        onSamples?(chunk)

        var chunkEnergy: Float = 0
        for s in chunk { chunkEnergy += s * s }
        let chunkRms = sqrt(chunkEnergy / Float(max(1, chunk.count)))
        if chunkRms >= 0.003 { heardAnySpeech = true }

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

    func finish() -> [Float] { queue.sync { samples } }

    func snapshot() -> [Float] { queue.sync { samples } }
}
