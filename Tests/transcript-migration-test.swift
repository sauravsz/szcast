import Foundation

@main
struct TranscriptMigrationTest {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("szcast-tmig-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let historyURL = root.appendingPathComponent("dictation-history.json")
        let notesURL = root.appendingPathComponent("meeting-notes.json")

        let legacyHistory = [
            DictationHistoryItem(text: "Legacy dictated phrase", rawText: "legacy dictated phrase", duration: 1.5),
            DictationHistoryItem(text: "Second legacy note", duration: 2.0)
        ]
        let legacyNotes = [
            MeetingNote(
                title: "Architecture Kickoff",
                duration: 600,
                transcript: "We decided to use SQLite FTS5.",
                summary: "Adopted unified SQLite storage.",
                actionItems: ["Benchmark search latency"],
                decisions: ["Use FTS5 unicode61"]
            )
        ]

        try JSONEncoder().encode(legacyHistory).write(to: historyURL)
        try JSONEncoder().encode(legacyNotes).write(to: notesURL)

        let store = TranscriptStore(
            databaseURL: root.appendingPathComponent("transcripts.sqlite3"),
            audioDirectory: root.appendingPathComponent("AudioRecordings", isDirectory: true)
        )

        TranscriptJSONMigration.run(into: store, historyFileURL: historyURL, notesFileURL: notesURL)
        guard store.records.count == 3 else {
            fatalError("Expected 3 migrated records, got \(store.records.count)")
        }

        // Running migration a second time must be idempotent.
        TranscriptJSONMigration.run(into: store, historyFileURL: historyURL, notesFileURL: notesURL)
        guard store.records.count == 3 else {
            fatalError("Migration was not idempotent: \(store.records.count)")
        }

        let notes = store.all(kind: .meeting)
        guard notes.count == 1, notes[0].actionItems == ["Benchmark search latency"],
            notes[0].decisions == ["Use FTS5 unicode61"]
        else {
            fatalError("Migrated MeetingNote metadata lost")
        }

        print("TranscriptJSONMigration tests passed")
    }
}
