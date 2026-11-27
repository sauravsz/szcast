@preconcurrency import AVFoundation
import Foundation
import os

@main
@MainActor
struct DictationCaptureTest {
    static func main() async throws {
        try await testBackgroundQueueTapBlockDoesNotTrap()
        try await testOfflineAVAudioEngineInstallTapReceivesResampledPCM()
        testBasicCaptureAndSystemTapLifecycle()
        print("Dictation capture concurrency tests passed")
    }

    private static func testBackgroundQueueTapBlockDoesNotTrap() async throws {
        guard let hwFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ),
            let target16k = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(DictationWire.sampleRate),
                channels: 1,
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(pcmFormat: hwFormat, frameCapacity: 1_024)
        else {
            fatalError("Failed to construct test AVAudioPCMBuffer")
        }

        buffer.frameLength = 1_024
        if let ch0 = buffer.floatChannelData?[0], let ch1 = buffer.floatChannelData?[1] {
            for i in 0..<1_024 {
                let sample = sin(Float(i) * 0.1) * 0.25
                ch0[i] = sample
                ch1[i] = sample * 0.5
            }
        }

        let collected = OSAllocatedUnfairLock(initialState: [Float]())
        let tapBlock = DictationCapture.makeAudioTapBlock(targetFormat: target16k) { samples in
            collected.withLock { $0.append(contentsOf: samples) }
        }

        // Execute tap closure on a background queue simulating AVFAudio's RealtimeMessenger.mServiceQueue.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            nonisolated(unsafe) let uncheckedBlock = tapBlock
            nonisolated(unsafe) let uncheckedBuffer = buffer
            let time = AVAudioTime(sampleTime: 0, atRate: 48_000)
            nonisolated(unsafe) let uncheckedTime = time
            DispatchQueue(label: "RealtimeMessenger.mServiceQueue.test").async {
                uncheckedBlock(uncheckedBuffer, uncheckedTime)
                continuation.resume()
            }
        }

        let out = collected.withLock { $0 }
        assertTrue(
            out.count >= 300 && out.count <= 400,
            "Expected ~341 16kHz resampled samples from 1024@48kHz buffer, got \(out.count)"
        )
        assertTrue(out.allSatisfy(\.isFinite), "All resampled samples must be finite")
    }

    private static func testOfflineAVAudioEngineInstallTapReceivesResampledPCM() async throws {
        guard let hwFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ),
            let target16k = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(DictationWire.sampleRate),
                channels: 1,
                interleaved: false
            )
        else {
            fatalError("Failed to construct audio formats")
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: hwFormat)
        try engine.enableManualRenderingMode(.offline, format: hwFormat, maximumFrameCount: 4_096)

        let totalSamples = OSAllocatedUnfairLock(initialState: 0)
        let tapBlock = DictationCapture.makeAudioTapBlock(targetFormat: target16k) { samples in
            totalSamples.withLock { $0 += samples.count }
        }
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1_024, format: hwFormat, block: tapBlock)
        try engine.start()

        guard let inBuf = AVAudioPCMBuffer(pcmFormat: hwFormat, frameCapacity: 4_096),
              let outBuf = AVAudioPCMBuffer(pcmFormat: hwFormat, frameCapacity: 4_096)
        else {
            fatalError("Failed to allocate render buffers")
        }
        inBuf.frameLength = 4_096
        if let dst = inBuf.floatChannelData?[0] {
            for i in 0..<4_096 { dst[i] = sin(Float(i) * 0.08) * 0.2 }
        }
        player.scheduleBuffer(inBuf, completionHandler: nil)
        player.play()

        for _ in 0..<3 {
            let status = try engine.renderOffline(4_096, to: outBuf)
            assertTrue(status != .error, "Offline render failed with status \(status)")
        }

        // Give AVFAudio's tap messenger queue a moment to deliver pending tap blocks.
        let deadline = ContinuousClock.now + .seconds(2)
        while totalSamples.withLock({ $0 }) == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()

        let count = totalSamples.withLock { $0 }
        assertTrue(count > 0, "Expected offline AVAudioNode tap to deliver >0 samples without trapping, got \(count)")
    }

    private static func testBasicCaptureAndSystemTapLifecycle() {
        let capture = DictationCapture()
        capture.setMuted(true)
        assertTrue(capture.isMuted, "Capture mute state toggles cleanly")
        capture.setMuted(false)
        _ = DictationCapture.isClamshellModeActive()

        let systemTap = SystemAudioTapCapture()
        assertTrue(!systemTap.isCapturing && systemTap.stop().isEmpty, "Idle SystemAudioTapCapture stops cleanly")
    }

    private static func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fatalError("Assertion failed: \(message)")
        }
        print("PASS  \(message)")
    }
}
