import Foundation

@main
struct TranscriptStoreTest {
    @MainActor
    static func main() throws {
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

        print("TranscriptStore & DictationHistoryStore SQLite/FTS5 tests passed")
    }
}
