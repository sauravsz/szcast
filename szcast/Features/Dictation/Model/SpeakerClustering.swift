import Foundation

enum SpeakerClusterer {
    struct LocalEmbedding: Sendable {
        var vector: [Float]
        var start: TimeInterval
        var end: TimeInterval
        var localSpeakerIndex: Int
    }

    static func l2Normalize(_ v: [Float]) -> [Float] {
        var sumSq: Float = 0
        for x in v { sumSq += x * x }
        let norm = sqrt(sumSq)
        guard norm > 1e-6 else { return v }
        return v.map { $0 / norm }
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 1e-6 ? dot / denom : 0
    }

    /// Average-linkage agglomerative clustering on L2-normalized speaker embeddings.
    static func cluster(
        embeddings: [LocalEmbedding],
        targetSpeakerCount: Int?,
        similarityThreshold: Float = 0.52
    ) -> [Int] {
        guard !embeddings.isEmpty else { return [] }
        let clampedTarget = targetSpeakerCount.map { max(1, min(12, $0)) }
        var clusters: [[Int]] = embeddings.indices.map { [$0] }
        let normalized = embeddings.map { l2Normalize($0.vector) }

        while clusters.count > 1 {
            if let clampedTarget, clusters.count <= clampedTarget { break }
            var bestPair: (Int, Int)?
            var bestSim: Float = -Float.greatestFiniteMagnitude
            for i in 0..<(clusters.count - 1) {
                for j in (i + 1)..<clusters.count {
                    let sim = averageSimilarity(clusters[i], clusters[j], vectors: normalized)
                    if sim > bestSim {
                        bestSim = sim
                        bestPair = (i, j)
                    }
                }
            }
            guard let (i, j) = bestPair else { break }
            if clampedTarget == nil && bestSim < similarityThreshold { break }
            clusters[i].append(contentsOf: clusters[j])
            clusters.remove(at: j)
        }

        // Order clusters deterministically by earliest speaking appearance.
        let ordered = clusters.sorted { lhs, rhs in
            let lStart = lhs.map { embeddings[$0].start }.min() ?? 0
            let rStart = rhs.map { embeddings[$0].start }.min() ?? 0
            return lStart < rStart
        }

        var assignments = [Int](repeating: 0, count: embeddings.count)
        for (clusterID, memberIndices) in ordered.enumerated() {
            for idx in memberIndices {
                assignments[idx] = clusterID
            }
        }
        return assignments
    }

    private static func averageSimilarity(_ lhs: [Int], _ rhs: [Int], vectors: [[Float]]) -> Float {
        var total: Float = 0
        var count = 0
        for a in lhs {
            for b in rhs {
                total += cosineSimilarity(vectors[a], vectors[b])
                count += 1
            }
        }
        return count > 0 ? total / Float(count) : 0
    }
}

enum DictationVADChunker {
    struct SpeechSpan: Equatable, Sendable {
        var startSample: Int
        var endSample: Int
    }

    /// Groups raw speech probability windows into padded, gap-merged speech spans.
    static func speechSpans(
        probabilities: [Float],
        hopSamples: Int,
        windowSamples: Int,
        totalSamples: Int,
        threshold: Float = 0.45,
        padSamples: Int = 4_800,
        mergeGapSamples: Int = 5_600
    ) -> [SpeechSpan] {
        guard totalSamples > 0, !probabilities.isEmpty else { return [] }
        var raw = [SpeechSpan]()
        var activeStart: Int?

        for (index, prob) in probabilities.enumerated() {
            let start = index * hopSamples
            let end = min(totalSamples, start + windowSamples)
            if prob >= threshold {
                if activeStart == nil { activeStart = max(0, start - padSamples) }
            } else if let s = activeStart {
                raw.append(SpeechSpan(startSample: s, endSample: min(totalSamples, end + padSamples)))
                activeStart = nil
            }
        }
        if let s = activeStart {
            raw.append(SpeechSpan(startSample: s, endSample: totalSamples))
        }
        guard !raw.isEmpty else { return [] }

        var merged = [raw[0]]
        for span in raw.dropFirst() {
            if span.startSample - merged[merged.count - 1].endSample <= mergeGapSamples {
                merged[merged.count - 1].endSample = max(merged[merged.count - 1].endSample, span.endSample)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// Fallback fast RMS energy VAD for tests or when Silero VAD weights aren't installed yet.
    static func energySpeechSpans(
        samples: [Float],
        sampleRate: Int = 16_000,
        windowMs: Int = 256,
        thresholdRMS: Float = 0.01
    ) -> [SpeechSpan] {
        let hopSamples = max(1, (sampleRate * windowMs) / 1000)
        var probs = [Float]()
        var idx = 0
        while idx < samples.count {
            let end = min(samples.count, idx + hopSamples)
            var sumSq: Float = 0
            for i in idx..<end { sumSq += samples[i] * samples[i] }
            let rms = sqrt(sumSq / Float(max(1, end - idx)))
            probs.append(rms >= thresholdRMS ? 1.0 : 0.0)
            idx += hopSamples
        }
        return speechSpans(
            probabilities: probs,
            hopSamples: hopSamples,
            windowSamples: hopSamples,
            totalSamples: samples.count
        )
    }
}
