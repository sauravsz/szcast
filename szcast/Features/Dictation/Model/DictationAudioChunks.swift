import Accelerate
import Foundation

enum DictationAudioChunks {
    /// Audio shorter than this never leaves the microphone: a round-trip costs more than it says.
    static let minimumLiveSamples = 32_000
    /// Forced flush without pause: bounds the final pass and how stale visible text gets.
    static let maximumLiveSamples = 8 * 16_000
    /// Audio re-transcribed with every flush so word splits at the cut rarely duplicate.
    static let liveOverlapSamples = 32_000

    static func liveOverlapStart(in samples: [Float], before start: Int) -> Int {
        precondition(start >= 0 && start <= samples.count)
        guard start > liveOverlapSamples else { return 0 }
        let window = 3_200
        let fallback = start - liveOverlapSamples
        func energy(at offset: Int) -> Float {
            samples[offset..<(offset + window)].reduce(Float.zero) { $0 + $1 * $1 }
        }
        var cut = fallback
        var best = energy(at: fallback)
        var offset = max(0, start - 48_000)
        while offset + window <= start {
            let candidate = energy(at: offset)
            if candidate < best { best = candidate; cut = offset + window / 2 }
            offset += 160
        }
        return cut
    }

    static func liveCut(in samples: [Float], from start: Int, to end: Int) -> Int {
        precondition(start >= 0 && start <= end && end <= samples.count)
        guard end - start >= minimumLiveSamples else { return start }
        var cut = end
        if end - start >= 3_200 {
            let window = 3_200
            var quietest: Float = .infinity
            for offset in stride(from: max(start, end - 48_000), through: end - window, by: 160) {
                let energy = samples[offset..<(offset + window)].reduce(Float.zero) { $0 + $1 * $1 }
                if energy <= quietest { quietest = energy; cut = offset + window / 2 }
            }
        }
        return cut
    }

    static func endsInPause(in samples: [Float], from start: Int, to end: Int) -> Bool {
        precondition(start >= 0 && start <= end && end <= samples.count)
        guard end - start >= minimumLiveSamples else { return false }
        let window = 3_200
        var peak: Float = 0
        var offset = start
        while offset + window <= end {
            let energy = samples[offset..<(offset + window)].reduce(Float.zero) { $0 + $1 * $1 }
            peak = max(peak, energy)
            offset += 1_600
        }
        guard peak > 0 else { return false }
        var tail: Float = 0
        var count = 0
        offset = max(start, end - 8_000)
        while offset + window <= end {
            tail += samples[offset..<(offset + window)].reduce(Float.zero) { $0 + $1 * $1 }
            count += 1
            offset += 1_600
        }
        guard count > 0 else { return false }
        return tail / Float(count) <= peak * 0.05
    }

    static func ranges(in samples: [Float], maximum: Int) -> [Range<Int>] {
        precondition(maximum > 0)
        var ranges = [Range<Int>]()
        var start = 0
        while start < samples.count {
            var end = min(start + maximum, samples.count)
            if end < samples.count, end - start >= 3200 {
                let window = 3200
                var quietest: Float = .infinity
                for offset in stride(from: max(start, end - 48_000), through: end - window, by: 160) {
                    let energy = samples[offset..<(offset + window)].reduce(Float.zero) { $0 + $1 * $1 }
                    if energy <= quietest { quietest = energy; end = offset + window / 2 }
                }
            }
            ranges.append(start..<end)
            start = end
        }
        return ranges
    }

    /// Conditions 16 kHz microphone audio using a vDSP biquad 80 Hz HPF, click suppression,
    /// active-speech RMS normalization (ignoring silences), and soft-knee peak limiting.
    static func conditionForTranscription(_ samples: [Float], whisperMode: Bool = false) -> [Float] {
        guard samples.count > 64 else { return samples }

        // 1. Remove scalar DC offset so turn-on transients never distort filter state.
        var mean: Float = 0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(samples.count))
        var dcRemoved = [Float](repeating: 0, count: samples.count)
        var negMean = -mean
        vDSP_vsadd(samples, 1, &negMean, &dcRemoved, 1, vDSP_Length(samples.count))

        // 2. 2nd-order Butterworth 80 Hz high-pass biquad @ 16 kHz.
        var filtered = [Float](repeating: 0, count: samples.count)
        let omega = 2.0 * Double.pi * 80.0 / 16_000.0
        let cosW = cos(omega)
        let alpha = sin(omega) / sqrt(2.0)
        let a0 = 1.0 + alpha
        let coefficients: [Double] = [
            (1.0 + cosW) / (2.0 * a0),
            -(1.0 + cosW) / a0,
            (1.0 + cosW) / (2.0 * a0),
            (-2.0 * cosW) / a0,
            (1.0 - alpha) / a0
        ]
        if let setup = vDSP_biquad_CreateSetup(coefficients, 1) {
            defer { vDSP_biquad_DestroySetup(setup) }
            var delays = [Float](repeating: 0, count: 4)
            vDSP_biquad(setup, &delays, dcRemoved, 1, &filtered, 1, vDSP_Length(samples.count))
        } else {
            filtered = dcRemoved
        }

        // 2b. In whisper mode, apply a +4.5 dB 2.5 kHz presence high-shelf so unvoiced consonants stay crisp.
        if whisperMode {
            applyWhisperPresenceShelf(&filtered)
        }

        // 3. Soft keystroke de-clicker on leading/trailing 40ms + 5ms cosine edge fades.
        suppressEdgeClicks(&filtered)

        // 3b. Soft stationary room/fan noise attenuation preserving speech transients cleanly.
        applyStationaryNoiseGate(&filtered)

        // 4. Active-speech RMS estimator (excludes silent frames so pauses do not skew leveling).
        var globalRMS: Float = 0
        vDSP_rmsqv(filtered, 1, &globalRMS, vDSP_Length(filtered.count))

        let frameLen = 800 // 50ms frames
        var activeRMSValues = [Float]()
        if filtered.count >= frameLen {
            var offset = 0
            while offset + frameLen <= filtered.count {
                var frameRMS: Float = 0
                filtered.withUnsafeBufferPointer { ptr in
                    if let base = ptr.baseAddress {
                        vDSP_rmsqv(base.advanced(by: offset), 1, &frameRMS, vDSP_Length(frameLen))
                    }
                }
                if frameRMS >= 0.0025 {
                    activeRMSValues.append(frameRMS)
                }
                offset += frameLen
            }
        }

        guard globalRMS >= 0.0015 || !activeRMSValues.isEmpty else { return filtered }

        let speechRMS: Float
        if !activeRMSValues.isEmpty {
            let sorted = activeRMSValues.sorted()
            // 65th percentile reflects conversational speech level while resisting isolated transient spikes.
            speechRMS = sorted[min(sorted.count - 1, (sorted.count * 65) / 100)]
        } else {
            speechRMS = globalRMS
        }
        guard speechRMS >= 0.0015 else { return filtered }

        let targetRMS: Float = whisperMode ? 0.085 : 0.072
        let maxGain: Float = whisperMode ? 6.5 : 4.2
        let gain = min(maxGain, max(1.0, targetRMS / speechRMS))
        if gain > 1.05 {
            var mutableGain = gain
            vDSP_vsmul(filtered, 1, &mutableGain, &filtered, 1, vDSP_Length(filtered.count))
        }

        // 5. Smooth soft-limiter above 0.85 prevents digital clipping on close-mic plosives.
        var peak: Float = 0
        vDSP_maxmgv(filtered, 1, &peak, vDSP_Length(filtered.count))
        if peak > 0.88 {
            for i in 0..<filtered.count {
                let s = filtered[i]
                let mag = abs(s)
                if mag > 0.85 {
                    let excess = mag - 0.85
                    let limited = 0.85 + excess / (1.0 + excess * 4.0)
                    filtered[i] = min(0.98, limited) * (s < 0 ? -1.0 : 1.0)
                }
            }
        }
        return filtered
    }

    private static func suppressEdgeClicks(_ samples: inout [Float]) {
        let count = samples.count
        guard count > 320 else { return }

        // Suppress isolated <8ms hotkey press/release click impulses in edge 40ms windows.
        let edgeWindow = min(640, count / 4)
        let interiorStart = edgeWindow
        let interiorEnd = count - edgeWindow
        if interiorEnd > interiorStart {
            var bodyRMS: Float = 0
            samples.withUnsafeBufferPointer { ptr in
                if let base = ptr.baseAddress {
                    vDSP_rmsqv(base.advanced(by: interiorStart), 1, &bodyRMS, vDSP_Length(interiorEnd - interiorStart))
                }
            }
            let spikeThreshold = max(0.08, bodyRMS * 5.0)
            for idx in 0..<edgeWindow where abs(samples[idx]) > spikeThreshold {
                samples[idx] *= 0.25
            }
            for idx in (count - edgeWindow)..<count where abs(samples[idx]) > spikeThreshold {
                samples[idx] *= 0.25
            }
        }

        // 5ms (80-sample) cosine taper at start & end avoids boundary discontinuities.
        let fadeSamples = min(80, count / 8)
        for i in 0..<fadeSamples {
            let weight = 0.5 - 0.5 * cos(Float.pi * Float(i) / Float(fadeSamples))
            samples[i] *= weight
            samples[count - 1 - i] *= weight
        }
    }

    private static func applyWhisperPresenceShelf(_ samples: inout [Float]) {
        guard samples.count > 16 else { return }
        // High-shelf biquad: +4.5 dB @ 2,500 Hz, fs = 16,000 Hz, slope S = 1 (Q = 1/sqrt(2))
        let gainDB = 4.5
        let A = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * Double.pi * 2_500.0 / 16_000.0
        let cosW = cos(w0)
        let sinW = sin(w0)
        let alpha = (sinW / 2.0) * sqrt((A + 1.0 / A) * (1.0 / 1.0 - 1.0) + 2.0)
        let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
        let a0 = (A + 1.0) - (A - 1.0) * cosW + twoSqrtAAlpha
        let coeffs: [Double] = [
            (A * ((A + 1.0) + (A - 1.0) * cosW + twoSqrtAAlpha)) / a0,
            (-2.0 * A * ((A - 1.0) + (A + 1.0) * cosW)) / a0,
            (A * ((A + 1.0) + (A - 1.0) * cosW - twoSqrtAAlpha)) / a0,
            (2.0 * ((A - 1.0) - (A + 1.0) * cosW)) / a0,
            ((A + 1.0) - (A - 1.0) * cosW - twoSqrtAAlpha) / a0
        ]
        guard let setup = vDSP_biquad_CreateSetup(coeffs, 1) else { return }
        defer { vDSP_biquad_DestroySetup(setup) }
        var output = [Float](repeating: 0, count: samples.count)
        var delays = [Float](repeating: 0, count: 4)
        vDSP_biquad(setup, &delays, samples, 1, &output, 1, vDSP_Length(samples.count))
        samples = output
    }

    private static func applyStationaryNoiseGate(_ samples: inout [Float]) {
        let hop = 320 // 20ms frames
        let frameCount = samples.count / hop
        guard frameCount >= 8 else { return }

        var rmsValues = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for f in 0..<frameCount {
                var val: Float = 0
                vDSP_rmsqv(base.advanced(by: f * hop), 1, &val, vDSP_Length(hop))
                rmsValues[f] = val
            }
        }
        let sorted = rmsValues.sorted()
        let noiseFloor = sorted[max(0, (sorted.count * 15) / 100)]
        let speechCeiling = sorted[min(sorted.count - 1, (sorted.count * 85) / 100)]
        guard noiseFloor > 0.0005, noiseFloor < 0.015, speechCeiling / max(1e-6, noiseFloor) >= 2.5 else {
            return
        }

        let gateThreshold = noiseFloor * 1.4
        var prevGain: Float = 1.0
        for f in 0..<frameCount {
            let targetGain: Float = rmsValues[f] < gateThreshold ? 0.30 : 1.0
            let start = f * hop
            let end = (f == frameCount - 1) ? samples.count : (start + hop)
            let span = max(1, end - start)
            if prevGain == targetGain {
                if targetGain < 0.99 {
                    var g = targetGain
                    samples.withUnsafeMutableBufferPointer { buf in
                        guard let base = buf.baseAddress else { return }
                        vDSP_vsmul(base.advanced(by: start), 1, &g, base.advanced(by: start), 1, vDSP_Length(span))
                    }
                }
            } else {
                // Smooth 20ms linear ramp prevents click discontinuities on gate transitions.
                let rampLen = min(span, hop)
                for i in 0..<rampLen {
                    let t = Float(i) / Float(rampLen)
                    samples[start + i] *= prevGain + (targetGain - prevGain) * t
                }
                if targetGain < 0.99 && rampLen < span {
                    for i in rampLen..<span { samples[start + i] *= targetGain }
                }
            }
            prevGain = targetGain
        }
    }

    /// Acoustic gate filtering out accidental brief (<150ms) key clicks before ASR wakeup.
    static func hasUsableSpeechEnergy(_ samples: [Float]) -> Bool {
        guard samples.count >= 2_400 else { return false }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        guard peak >= 0.005 else { return false }
        let frame = 800
        var activeFrames = 0
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            var offset = 0
            while offset + frame <= samples.count {
                var rms: Float = 0
                vDSP_rmsqv(base.advanced(by: offset), 1, &rms, vDSP_Length(frame))
                if rms >= 0.0022 {
                    activeFrames += 1
                    if activeFrames >= 2 { return }
                }
                offset += frame
            }
        }
        return activeFrames >= 2
    }
}
