import CoreML
import Foundation

final class SpeakerDiarizer {
    private static let chunkSamples = 160_000
    private static let hopSamples = 80_000
    private static let segmentationFrames = 589
    private static let powersetClasses = 7
    private static let embeddingDimension = 256
    private static let maxBatch = 8

    private let segmentation: MLModel
    private let fbank: MLModel
    private let embedding: MLModel

    init(directory: URL) throws {
        segmentation = try DictationTensor.load("Segmentation", at: directory, units: .cpuAndGPU)
        fbank = try DictationTensor.load("FBank", at: directory, units: .cpuOnly)
        embedding = try DictationTensor.load("Embedding", at: directory, units: .cpuAndGPU)
    }

    func diarize(
        samples: [Float],
        speakerCount: Int?,
        labelPrefix: String = "Speaker"
    ) throws -> [SpeakerTurn] {
        guard samples.count >= 8_000 else { return [] }

        var chunkStarts = [Int]()
        var cursor = 0
        while cursor < samples.count {
            chunkStarts.append(cursor)
            if cursor + Self.chunkSamples >= samples.count { break }
            cursor += Self.hopSamples
        }

        var localEmbeddings = [SpeakerClusterer.LocalEmbedding]()
        var chunkSpeakerWeights = [[[Float]]](
            repeating: [[Float]](repeating: [], count: 3), count: chunkStarts.count)

        for batchStart in stride(from: 0, to: chunkStarts.count, by: Self.maxBatch) {
            let batchEnd = min(chunkStarts.count, batchStart + Self.maxBatch)
            let batchCount = batchEnd - batchStart

            let audioTensor = try DictationTensor.zeros([batchCount, 1, Self.chunkSamples])
            audioTensor.withUnsafeMutableBufferPointer(ofType: Float.self) { target, _ in
                target.initialize(repeating: 0)
                for b in 0..<batchCount {
                    let start = chunkStarts[batchStart + b]
                    let copyCount = min(Self.chunkSamples, samples.count - start)
                    let base = b * Self.chunkSamples
                    for i in 0..<copyCount {
                        target[base + i] = samples[start + i]
                    }
                }
            }

            let segOut = try DictationTensor.predict(segmentation, ["audio": audioTensor])
            let logProbsArray = try DictationTensor.array("log_probs", from: segOut)
            let fbankOut = try DictationTensor.predict(fbank, ["audio": audioTensor])
            let fbankArray = try DictationTensor.array("fbank_features", from: fbankOut)

            let logProbs = try DictationTensor.floatValues(from: logProbsArray)
            let fbankValues = try DictationTensor.floatValues(from: fbankArray)
            let fbankStride = 80 * 998

            for b in 0..<batchCount {
                let chunkIndex = batchStart + b
                let chunkStartTime = Double(chunkStarts[chunkIndex]) / Double(DictationWire.sampleRate)
                let frameStride = Self.segmentationFrames * Self.powersetClasses
                let chunkLogBase = b * frameStride

                var singleWeights = [[Float]](repeating: [Float](repeating: 0, count: Self.segmentationFrames), count: 3)
                var totalWeights = [[Float]](repeating: [Float](repeating: 0, count: Self.segmentationFrames), count: 3)

                for frame in 0..<Self.segmentationFrames {
                    let offset = chunkLogBase + frame * Self.powersetClasses
                    let p0 = exp(logProbs[offset + 1])
                    let p1 = exp(logProbs[offset + 2])
                    let p2 = exp(logProbs[offset + 3])
                    let p01 = exp(logProbs[offset + 4])
                    let p02 = exp(logProbs[offset + 5])
                    let p12 = exp(logProbs[offset + 6])

                    singleWeights[0][frame] = p0
                    singleWeights[1][frame] = p1
                    singleWeights[2][frame] = p2
                    totalWeights[0][frame] = p0 + p01 + p02
                    totalWeights[1][frame] = p1 + p01 + p12
                    totalWeights[2][frame] = p2 + p02 + p12
                }
                chunkSpeakerWeights[chunkIndex] = totalWeights

                let chunkFbankTensor = try DictationTensor.zeros([1, 1, 80, 998])
                chunkFbankTensor.withUnsafeMutableBufferPointer(ofType: Float.self) { dst, _ in
                    let srcBase = b * fbankStride
                    for idx in 0..<fbankStride {
                        dst[idx] = fbankValues[srcBase + idx]
                    }
                }

                for spk in 0..<3 {
                    let activeSum = singleWeights[spk].reduce(0, +)
                    guard activeSum >= 12.0 else { continue }
                    let weightTensor = try DictationTensor.zeros([1, Self.segmentationFrames])
                    weightTensor.withUnsafeMutableBufferPointer(ofType: Float.self) { dst, _ in
                        for f in 0..<Self.segmentationFrames { dst[f] = singleWeights[spk][f] }
                    }
                    let embOut = try DictationTensor.predict(
                        embedding,
                        ["fbank_features": chunkFbankTensor, "weights": weightTensor]
                    )
                    let embArray = try DictationTensor.array("embedding", from: embOut)
                    let vec = Array(try DictationTensor.floatValues(from: embArray).prefix(Self.embeddingDimension))
                    localEmbeddings.append(
                        SpeakerClusterer.LocalEmbedding(
                            vector: vec,
                            start: chunkStartTime,
                            end: chunkStartTime + 10.0,
                            localSpeakerIndex: chunkIndex * 3 + spk
                        )
                    )
                }
            }
        }

        guard !localEmbeddings.isEmpty else { return [] }
        let assignments = SpeakerClusterer.cluster(
            embeddings: localEmbeddings, targetSpeakerCount: speakerCount)
        var localToGlobal = [Int: Int]()
        for (idx, item) in localEmbeddings.enumerated() {
            localToGlobal[item.localSpeakerIndex] = assignments[idx]
        }

        let numClusters = (assignments.max() ?? 0) + 1
        let frameSeconds = 10.0 / Double(Self.segmentationFrames)
        let totalDuration = Double(samples.count) / Double(DictationWire.sampleRate)
        let totalTimelineFrames = max(1, Int(ceil(totalDuration / frameSeconds)))
        var clusterScores = [[Float]](
            repeating: [Float](repeating: 0, count: numClusters), count: totalTimelineFrames)
        var frameTotals = [Float](repeating: 0, count: totalTimelineFrames)

        for chunkIndex in chunkStarts.indices {
            let chunkOffsetFrames = Int(
                round((Double(chunkStarts[chunkIndex]) / Double(DictationWire.sampleRate)) / frameSeconds))
            for frame in 0..<Self.segmentationFrames {
                let globalFrame = chunkOffsetFrames + frame
                guard globalFrame < totalTimelineFrames else { break }
                // Center-weighted blending across overlapping 10s chunks.
                let rel = Double(frame) / Double(Self.segmentationFrames - 1)
                let envelope = Float(1.0 - abs(rel - 0.5) * 0.8)
                frameTotals[globalFrame] += envelope
                for spk in 0..<3 {
                    guard let clusterID = localToGlobal[chunkIndex * 3 + spk] else { continue }
                    clusterScores[globalFrame][clusterID] += chunkSpeakerWeights[chunkIndex][spk][frame] * envelope
                }
            }
        }

        var turns = [SpeakerTurn]()
        var activeCluster: Int?
        var activeStart: TimeInterval = 0

        for frame in 0..<totalTimelineFrames {
            let denom = max(1e-4, frameTotals[frame])
            var bestCluster = 0
            var bestScore: Float = 0
            for cid in 0..<numClusters {
                let score = clusterScores[frame][cid] / denom
                if score > bestScore {
                    bestScore = score
                    bestCluster = cid
                }
            }
            let resolved: Int? = bestScore >= 0.35 ? bestCluster : nil
            let time = Double(frame) * frameSeconds
            if resolved != activeCluster {
                if let prev = activeCluster, time - activeStart >= 0.3 {
                    let label = "\(labelPrefix) \(prev + 1)"
                    if var last = turns.last, last.speaker == label, activeStart - last.end <= 0.6 {
                        last.end = time
                        turns[turns.count - 1] = last
                    } else {
                        turns.append(SpeakerTurn(speaker: label, start: activeStart, end: time))
                    }
                }
                activeCluster = resolved
                activeStart = time
            }
        }
        if let prev = activeCluster, totalDuration - activeStart >= 0.3 {
            let label = "\(labelPrefix) \(prev + 1)"
            turns.append(SpeakerTurn(speaker: label, start: activeStart, end: totalDuration))
        }
        return turns
    }
}
