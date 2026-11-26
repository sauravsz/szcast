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

    /// Conditions 16 kHz microphone audio with an 80 Hz high-pass filter and bounded RMS leveling.
    static func conditionForTranscription(_ samples: [Float], whisperMode: Bool = false) -> [Float] {
        guard samples.count > 64 else { return samples }

        // First-order 80 Hz DC/high-pass filter at 16 kHz removes laptop fan rumble and plosives.
        var filtered = [Float](repeating: 0, count: samples.count)
        let alpha: Float = 0.969
        filtered[0] = samples[0]
        var prevX = samples[0]
        var prevY = filtered[0]
        for i in 1..<samples.count {
            let x = samples[i]
            let y = alpha * (prevY + x - prevX)
            filtered[i] = y
            prevX = x
            prevY = y
        }

        var rms: Float = 0
        vDSP_rmsqv(filtered, 1, &rms, vDSP_Length(filtered.count))
        guard rms >= 0.0015 else { return filtered }

        let targetRMS: Float = 0.065
        let maxGain: Float = whisperMode ? 6.5 : 4.0
        let gain = min(maxGain, max(1.0, targetRMS / rms))
        if gain > 1.05 {
            var mutableGain = gain
            vDSP_vsmul(filtered, 1, &mutableGain, &filtered, 1, vDSP_Length(filtered.count))
        }

        var peak: Float = 0
        vDSP_maxmgv(filtered, 1, &peak, vDSP_Length(filtered.count))
        if peak > 0.88 {
            // Smooth soft-limiter above 0.85 avoids digital clipping on close mic plosives.
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
}
