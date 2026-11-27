import Foundation

@main
struct TranscriptStoreTest {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("szcast-tstore-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let dbURL = root.appendingPathComponent("transcripts.sqlite3")
        let audioDir = root.appendingPathComponent("AudioRecordings", isDirectory: true)

        let store = TranscriptStore(databaseURL: dbURL, audioDirectory: audioDir)

        // Verify unlimited storage (>250 items, removing legacy 250-item cap).
        for idx in 0..<310 {
            let rec = TranscriptRecord(
                kind: .dictation,
                title: "Session \(idx)",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(idx)),
                duration: 3.5,
                text: idx == 150 ? "Quantum computing roadmap review" : "Routine note number \(idx)"
            )
            guard store.upsert(rec, refreshCache: false) else {
                fatalError("Failed to insert record \(idx)")
            }
        }
        store.reload(limit: 400)
        guard store.records.count == 310 else {
            fatalError("Expected 310 records, got \(store.records.count)")
        }

        // Verify FTS5 prefix & multi-term search.
        let hits = store.search(query: "quant road")
        guard hits.count == 1, hits[0].title == "Session 150" else {
            fatalError("FTS5 search failed: \(hits.map(\.title))")
        }

        // Verify speaker attribution rename & undo-friendly find/replace.
        let meeting = TranscriptRecord(
            kind: .meeting,
            title: "Design Sync",
            duration: 12.0,
            text: "Others 1: Let's ship Parakeet V3.\nMe: Agreed, Parakeet is fast.",
            segments: [
                TranscriptSegment(speaker: "Others 1", text: "Let's ship Parakeet V3.", start: 0, end: 5),
                TranscriptSegment(speaker: "Me", text: "Agreed, Parakeet is fast.", start: 5.5, end: 11)
            ]
        )
        store.upsert(meeting)
        let renamed = meeting.renamingSpeaker("Others 1", to: "Alice")
        guard renamed.speakerNames == ["Alice", "Me"] else {
            fatalError("Speaker rename failed: \(renamed.speakerNames)")
        }
        let (replaced, count) = renamed.replacingOccurrences(of: "parakeet", with: "Nemotron", caseSensitive: false)
        guard count >= 2, replaced.text.contains("Nemotron") else {
            fatalError("Case-insensitive replace failed")
        }
        store.upsert(replaced)
        let ftsSpeaker = store.search(query: "Alice", kind: .meeting)
        guard ftsSpeaker.contains(where: { $0.id == replaced.id }) else {
            fatalError("Speaker name not indexed in FTS5")
        }

        // Verify DictationHistoryStore backing and WAV retention.
        let historyJSON = root.appendingPathComponent("dictation-history.json")
        let historyStore = DictationHistoryStore(fileURL: historyJSON, audioDirectory: audioDir)
        let pcm = [Float](repeating: 0.1, count: 16_000)
        historyStore.add(
            text: "Test timed entry",
            rawText: "test timed entry",
            duration: 1.0,
            samples: pcm,
            words: [
                TranscriptWord(text: "Test", start: 0.0, end: 0.3),
                TranscriptWord(text: "timed", start: 0.3, end: 0.6),
                TranscriptWord(text: "entry", start: 0.6, end: 0.9)
            ],
            modelID: "redux"
        )
        guard let item = historyStore.items.first(where: { $0.text == "Test timed entry" }),
            historyStore.audioURL(for: item) != nil
        else {
            fatalError("DictationHistoryStore failed to persist WAV or record")
        }

        // Verify async compressed .m4a persistence + instant optimistic prepend.
        let asyncAudio = (0..<16_000).map { Float(sin(2 * Double.pi * 440 * Double($0) / 16_000) * 0.2) }
        historyStore.addAsync(
            text: "Async compressed test entry",
            rawText: "async compressed test entry",
            duration: 1.0,
            samples: asyncAudio,
            modelID: "ultra"
        )
        guard historyStore.items.first?.text == "Async compressed test entry" else {
            fatalError("DictationHistoryStore.addAsync failed immediate in-memory prepend")
        }
        await historyStore.flushPendingWrites()
        guard let asyncItem = historyStore.items.first(where: { $0.text == "Async compressed test entry" }),
              let asyncURL = historyStore.audioURL(for: asyncItem),
              asyncURL.pathExtension == "m4a"
        else {
            fatalError("DictationHistoryStore.addAsync failed compressed m4a persistence")
        }

        // Verify .m4a audio reload + multi-model transcription update in store & FTS5 index.
        guard let decodedSamples = DictationHistoryStore.loadAudioSamples(from: asyncURL),
              decodedSamples.count >= 14_000
        else {
            fatalError("DictationHistoryStore.loadAudioSamples failed to decode m4a archive")
        }
        historyStore.updateTranscription(
            id: asyncItem.id,
            text: "Re-transcribed quantum summary",
            rawText: "re-transcribed quantum summary",
            modelID: "ultra"
        )
        let updatedHits = historyStore.store.search(query: "Re-transcribed quantum", kind: .dictation)
        guard historyStore.items.first(where: { $0.id == asyncItem.id })?.text == "Re-transcribed quantum summary",
              updatedHits.contains(where: { $0.id == asyncItem.id })
        else {
            fatalError("DictationHistoryStore.updateTranscription failed memory or FTS5 sync")
        }

        // Verify incremental history pagination (60-item window) and FTS5 search query routing.
        for idx in 0..<75 {
            historyStore.store.upsert(
                TranscriptRecord(
                    kind: .dictation,
                    title: "Paged \(idx)",
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(idx)),
                    duration: 1.5,
                    text: idx == 5 ? "Unique paginated query target" : "Paged dictation item \(idx)"
                ),
                refreshCache: false
            )
        }
        historyStore.refreshItems()
        guard historyStore.items.count == 60, historyStore.hasMoreItems else {
            fatalError("Pagination expected 60 items initially, got \(historyStore.items.count)")
        }
        historyStore.refreshItems(query: "paginated query target")
        guard historyStore.items.count == 1 && !historyStore.hasMoreItems else {
            fatalError("FTS5 query search via DictationHistoryStore failed")
        }
        historyStore.refreshItems(query: "")
        historyStore.loadMore()
        guard historyStore.items.count > 60 else {
            fatalError("loadMore failed to advance page limit")
        }

        // Verify Text-Only audio retention preserves failed recovery clips while pruning completed recordings.
        historyStore.addAsync(
            text: "[Dictation Recovery — failed transcription]",
            rawText: "hiccup",
            duration: 1.2,
            samples: asyncAudio,
            modelID: "ultra"
        )
        await historyStore.flushPendingWrites()
        let recoveryItem = historyStore.items.first(where: { $0.text == "[Dictation Recovery — failed transcription]" })!
        historyStore.applyRetentionPolicy(days: 0)
        guard historyStore.audioURL(for: recoveryItem) != nil,
              let purgedCompleted = historyStore.items.first(where: { $0.id == asyncItem.id }),
              historyStore.audioURL(for: purgedCompleted) == nil
        else {
            fatalError("Audio retention policy failed to prune completed audio or dropped recovery clip")
        }

        print("TranscriptStore & DictationHistoryStore SQLite/FTS5 tests passed")
    }
}
