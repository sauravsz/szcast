import Foundation

/// One-shot import of legacy JSON dictation history and meeting notes into SQLite.
enum TranscriptJSONMigration {
    @MainActor
    static func run(
        into store: TranscriptStore,
        historyFileURL: URL? = nil,
        notesFileURL: URL? = nil
    ) {
        let support = AppPaths.applicationSupport()
        let history = historyFileURL ?? support.appendingPathComponent("dictation-history.json")
        let notes = notesFileURL ?? support.appendingPathComponent("meeting-notes.json")
        store.importLegacyJSONIfNeeded(historyFileURL: history, notesFileURL: notes)
    }
}
