import Foundation

@main
struct DictationVADDiarizationTest {
    static func main() {
        // 1. Validate VAD span detection & gap merging.
        var samples = [Float](repeating: 0, count: 16_000 * 6)
        // Burst 1: 1.0s .. 2.0s
        for i in 16_000..<32_000 { samples[i] = 0.25 * sin(Float(i) * 0.1) }
        // Burst 2: 4.0s .. 5.2s
        for i in 64_000..<83_200 { samples[i] = 0.25 * sin(Float(i) * 0.15) }

        let spans = DictationVADChunker.energySpeechSpans(samples: samples)
        guard spans.count == 2,
            spans[0].startSample < 20_000,
            spans[1].startSample > 50_000
        else {
            fatalError("VAD spans unexpected: \(spans)")
        }

        // 2. Validate AHC Speaker Clustering (Auto & pinned N).
        let embeddings: [SpeakerClusterer.LocalEmbedding] = [
            .init(vector: [1, 0, 0, 0], start: 0.0, end: 2.0, localSpeakerIndex: 0),
            .init(vector: [0.98, 0.1, 0, 0], start: 2.5, end: 4.0, localSpeakerIndex: 1),
            .init(vector: [0, 1, 0, 0], start: 5.0, end: 7.0, localSpeakerIndex: 2),
            .init(vector: [0.05, 0.99, 0, 0], start: 8.0, end: 10.0, localSpeakerIndex: 3)
        ]
        let autoLabels = SpeakerClusterer.cluster(embeddings: embeddings, targetSpeakerCount: nil)
        guard autoLabels == [0, 0, 1, 1] else {
            fatalError("Auto speaker clustering failed: \(autoLabels)")
        }
        let forcedThree = SpeakerClusterer.cluster(embeddings: embeddings, targetSpeakerCount: 3)
        guard Set(forcedThree).count == 3 else {
            fatalError("Pinned speaker count=3 failed: \(forcedThree)")
        }

        // 3. Validate Nemotron + Support models metadata invariants.
        guard DictationModel.nemotron.revision.count == 40,
            DictationModel.nemotron.requiredFiles.isSuperset(of: DictationModel.nemotron.components)
        else {
            fatalError("Nemotron model spec invalid")
        }
        for sup in DictationSupportModel.allCases {
            guard sup.revision.count == 40, !sup.components.isEmpty,
                sup.requiredFiles.isSuperset(of: sup.components)
            else {
                fatalError("Support model \(sup) metadata invalid")
            }
        }

        // 4. Validate sectioned chunk splitting & structured notes parser.
        let words = (1...120).map { $0 % 20 == 0 ? "word\($0)." : "word\($0)" }.joined(separator: " ")
        let chunks = TranscriptAIService.splitIntoWordChunks(words, maxWords: 50)
        guard chunks.count >= 2 && chunks.joined(separator: " ").split(separator: " ").count == 120 else {
            fatalError("Word chunk splitting lost content")
        }
        let parsed = TranscriptAIService.parseStructuredNotes("""
            TITLE: Sprint Sync
            SUMMARY:
            Reviewed Q4 deliverables.
            ACTION ITEMS:
            - Finalize API
            DECISIONS:
            - Freeze scope Friday
            """, fallbackTitle: "Fallback")
        guard parsed.title == "Sprint Sync",
            parsed.summary == "Reviewed Q4 deliverables.",
            parsed.actionItems == ["Finalize API"],
            parsed.decisions == ["Freeze scope Friday"]
        else {
            fatalError("Structured note parse failed: \(parsed)")
        }

        print("VAD, Diarization Clustering, Nemotron & Sectioned Notes tests passed")
    }
}
