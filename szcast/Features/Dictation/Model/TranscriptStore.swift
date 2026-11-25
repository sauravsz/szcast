import Foundation
import SQLite3

extension TranscriptRecord {
    init(from item: DictationHistoryItem) {
        self.init(
            id: item.id,
            kind: .dictation,
            title: Self.defaultTitle(for: item.text, kind: .dictation, date: item.timestamp),
            createdAt: item.timestamp,
            duration: item.duration,
            text: item.text,
            rawText: item.rawText,
            audioFilename: item.audioFilename,
            appName: item.appName,
            appBundleID: item.appBundleID,
            wordCount: item.wordCount
        )
    }

    init(from note: MeetingNote) {
        self.init(
            id: note.id,
            kind: .meeting,
            title: note.title,
            createdAt: note.date,
            duration: note.duration,
            text: note.transcript,
            rawText: note.transcript,
            summary: note.summary,
            actionItems: note.actionItems,
            decisions: note.decisions
        )
    }

    func toHistoryItem() -> DictationHistoryItem {
        DictationHistoryItem(
            id: id,
            timestamp: createdAt,
            text: text,
            rawText: rawText,
            duration: duration,
            appName: appName,
            appBundleID: appBundleID,
            audioFilename: audioFilename
        )
    }

    func toMeetingNote() -> MeetingNote {
        MeetingNote(
            id: id,
            title: title,
            date: createdAt,
            duration: duration,
            transcript: text,
            summary: summary,
            actionItems: actionItems,
            decisions: decisions
        )
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Unified SQLite + FTS5 persistence for dictations, meetings, and media/URL/podcast transcripts.
@MainActor
@Observable
final class TranscriptStore {
    let databaseURL: URL
    let audioDirectory: URL
    private(set) var records: [TranscriptRecord] = []

    @ObservationIgnored private var db: OpaquePointer?

    static var defaultDatabaseURL: URL {
        AppPaths.applicationSupport().appendingPathComponent("transcripts.sqlite3")
    }

    static var defaultAudioDirectory: URL {
        AppPaths.applicationSupport().appendingPathComponent("AudioRecordings", isDirectory: true)
    }

    init(databaseURL: URL? = nil, audioDirectory: URL? = nil) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL
        self.audioDirectory = audioDirectory ?? Self.defaultAudioDirectory
        prepareDirectories()
        openDatabase()
        reload()
    }

    isolated deinit {
        if let db { sqlite3_close_v2(db) }
    }

    func reload(limit: Int = 500) {
        records = fetchAll(kind: nil, limit: limit)
    }

    func all(kind: TranscriptRecordKind? = nil, limit: Int = 500, offset: Int = 0) -> [TranscriptRecord] {
        fetchAll(kind: kind, limit: limit, offset: offset)
    }

    func record(id: UUID) -> TranscriptRecord? {
        guard let db else { return nil }
        let sql = "SELECT \(Self.columns) FROM transcripts WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Self.decodeRow(stmt)
    }

    func search(query: String, kind: TranscriptRecordKind? = nil, limit: Int = 200) -> [TranscriptRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all(kind: kind, limit: limit) }
        guard let db else { return [] }
        let ftsQuery = Self.buildFTSQuery(trimmed)
        if let ftsQuery {
            let kindClause = kind == nil ? "" : " AND t.kind = ?"
            let sql = """
                SELECT \(Self.aliasedColumns)
                FROM transcripts_fts f
                JOIN transcripts t ON t.id = f.id
                WHERE transcripts_fts MATCH ?\(kindClause)
                ORDER BY t.created_at DESC
                LIMIT ?;
                """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, ftsQuery, -1, sqliteTransient)
                var nextBind: Int32 = 2
                if let kind {
                    sqlite3_bind_text(stmt, nextBind, kind.rawValue, -1, sqliteTransient)
                    nextBind += 1
                }
                sqlite3_bind_int(stmt, nextBind, Int32(max(1, limit)))
                let matches = Self.readRows(stmt)
                if !matches.isEmpty { return matches }
            }
        }
        return likeSearch(query: trimmed, kind: kind, limit: limit)
    }

    @discardableResult
    func upsert(_ record: TranscriptRecord, refreshCache: Bool = true) -> Bool {
        guard let db else { return false }
        let sql = """
            INSERT INTO transcripts(\(Self.columns))
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
              kind=excluded.kind,
              title=excluded.title,
              created_at=excluded.created_at,
              duration=excluded.duration,
              text=excluded.text,
              raw_text=excluded.raw_text,
              summary=excluded.summary,
              action_items_json=excluded.action_items_json,
              decisions_json=excluded.decisions_json,
              segments_json=excluded.segments_json,
              source_url=excluded.source_url,
              audio_filename=excluded.audio_filename,
              app_name=excluded.app_name,
              app_bundle_id=excluded.app_bundle_id,
              model_id=excluded.model_id,
              word_count=excluded.word_count,
              updated_at=excluded.updated_at;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return false }
        defer { sqlite3_finalize(stmt) }

        let encoder = JSONEncoder()
        let actionsJSON = (try? String(data: encoder.encode(record.actionItems), encoding: .utf8)) ?? "[]"
        let decisionsJSON = (try? String(data: encoder.encode(record.decisions), encoding: .utf8)) ?? "[]"
        let segmentsJSON = (try? String(data: encoder.encode(record.segments), encoding: .utf8)) ?? "[]"

        sqlite3_bind_text(stmt, 1, record.id.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, record.kind.rawValue, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, record.title, -1, sqliteTransient)
        sqlite3_bind_double(stmt, 4, record.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 5, record.duration)
        sqlite3_bind_text(stmt, 6, record.text, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 7, record.rawText, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 8, record.summary, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 9, actionsJSON, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 10, decisionsJSON, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 11, segmentsJSON, -1, sqliteTransient)
        bindOptionalText(stmt, index: 12, value: record.sourceURL)
        bindOptionalText(stmt, index: 13, value: record.audioFilename)
        bindOptionalText(stmt, index: 14, value: record.appName)
        bindOptionalText(stmt, index: 15, value: record.appBundleID)
        bindOptionalText(stmt, index: 16, value: record.modelID)
        sqlite3_bind_int(stmt, 17, Int32(record.wordCount))
        sqlite3_bind_double(stmt, 18, record.updatedAt.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else { return false }
        syncFTS(for: record)
        if refreshCache {
            if let existing = records.firstIndex(where: { $0.id == record.id }) {
                records[existing] = record
                records.sort { $0.createdAt > $1.createdAt }
            } else {
                records.insert(record, at: 0)
                records.sort { $0.createdAt > $1.createdAt }
            }
        }
        return true
    }

    func delete(id: UUID) {
        let existingAudio = record(id: id)?.audioFilename
        guard let db else { return }
        deleteSQL(db, sql: "DELETE FROM transcripts WHERE id = ?;", id: id.uuidString)
        deleteSQL(db, sql: "DELETE FROM transcripts_fts WHERE id = ?;", id: id.uuidString)
        if let existingAudio {
            let url = audioDirectory.appendingPathComponent(existingAudio)
            try? FileManager.default.removeItem(at: url)
        }
        records.removeAll { $0.id == id }
    }

    func clearAll(kind: TranscriptRecordKind? = nil) {
        guard let db else { return }
        if let kind {
            let toRemove = all(kind: kind, limit: 10_000)
            for item in toRemove {
                if let audio = item.audioFilename {
                    try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(audio))
                }
            }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM transcripts WHERE kind = ?;", -1, &stmt, nil) == SQLITE_OK,
                let stmt
            {
                sqlite3_bind_text(stmt, 1, kind.rawValue, -1, sqliteTransient)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            exec("DELETE FROM transcripts_fts WHERE id NOT IN (SELECT id FROM transcripts);")
            records.removeAll { $0.kind == kind }
        } else {
            exec("DELETE FROM transcripts; DELETE FROM transcripts_fts;")
            try? FileManager.default.removeItem(at: audioDirectory)
            prepareDirectories()
            records = []
        }
    }

    func purgeAudioOlderThan(days: Int, kind: TranscriptRecordKind = .dictation) {
        guard days > 0, let db else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
        let sql = """
            SELECT id, audio_filename FROM transcripts
            WHERE kind = ? AND created_at < ? AND audio_filename IS NOT NULL;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, kind.rawValue, -1, sqliteTransient)
        sqlite3_bind_double(stmt, 2, cutoff)
        var cleared = [String]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Self.string(stmt, 0)
            if let file = Self.optionalString(stmt, 1) {
                try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(file))
            }
            cleared.append(id)
        }
        guard !cleared.isEmpty else { return }
        var clearStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE transcripts SET audio_filename = NULL WHERE id = ?;", -1, &clearStmt, nil) == SQLITE_OK,
            let clearStmt
        {
            for id in cleared {
                sqlite3_reset(clearStmt)
                sqlite3_clear_bindings(clearStmt)
                sqlite3_bind_text(clearStmt, 1, id, -1, sqliteTransient)
                sqlite3_step(clearStmt)
            }
            sqlite3_finalize(clearStmt)
        }
        reload()
    }

    func audioURL(for record: TranscriptRecord) -> URL? {
        guard let name = record.audioFilename, !name.isEmpty else { return nil }
        let candidate = audioDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        return nil
    }

    /// One-shot idempotent import of legacy `dictation-history.json` and `meeting-notes.json`.
    @discardableResult
    func importLegacyJSONIfNeeded(historyFileURL: URL, notesFileURL: URL) -> Int {
        var imported = 0
        let decoder = JSONDecoder()

        if !hasMigrationFlag("legacy_history_json"),
            FileManager.default.fileExists(atPath: historyFileURL.path),
            let data = try? Data(contentsOf: historyFileURL),
            let legacy = try? decoder.decode([DictationHistoryItem].self, from: data)
        {
            for item in legacy where record(id: item.id) == nil {
                if upsert(TranscriptRecord(from: item), refreshCache: false) { imported += 1 }
            }
            setMigrationFlag("legacy_history_json")
        }

        if !hasMigrationFlag("legacy_notes_json"),
            FileManager.default.fileExists(atPath: notesFileURL.path),
            let data = try? Data(contentsOf: notesFileURL),
            let legacy = try? decoder.decode([MeetingNote].self, from: data)
        {
            for note in legacy where record(id: note.id) == nil {
                if upsert(TranscriptRecord(from: note), refreshCache: false) { imported += 1 }
            }
            setMigrationFlag("legacy_notes_json")
        }

        if imported > 0 { reload() }
        return imported
    }

    // MARK: - SQLite internals

    private func prepareDirectories() {
        let dir = databaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(
            at: audioDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private func openDatabase() {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            return
        }
        db = handle
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        sqlite3_busy_timeout(handle, 5_000)
        exec("""
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            CREATE TABLE IF NOT EXISTS transcripts(
              id TEXT PRIMARY KEY,
              kind TEXT NOT NULL,
              title TEXT NOT NULL,
              created_at REAL NOT NULL,
              duration REAL NOT NULL,
              text TEXT NOT NULL,
              raw_text TEXT NOT NULL,
              summary TEXT NOT NULL,
              action_items_json TEXT NOT NULL,
              decisions_json TEXT NOT NULL,
              segments_json TEXT NOT NULL,
              source_url TEXT,
              audio_filename TEXT,
              app_name TEXT,
              app_bundle_id TEXT,
              model_id TEXT,
              word_count INTEGER NOT NULL,
              updated_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS transcripts_created_idx ON transcripts(created_at DESC);
            CREATE INDEX IF NOT EXISTS transcripts_kind_idx ON transcripts(kind, created_at DESC);
            CREATE VIRTUAL TABLE IF NOT EXISTS transcripts_fts USING fts5(
              id UNINDEXED,
              title,
              text,
              summary,
              speaker_names,
              source_url,
              tokenize = 'unicode61'
            );
            CREATE TABLE IF NOT EXISTS transcripts_meta(
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            """)
    }

    private func syncFTS(for record: TranscriptRecord) {
        guard let db else { return }
        deleteSQL(db, sql: "DELETE FROM transcripts_fts WHERE id = ?;", id: record.id.uuidString)
        let sql = """
            INSERT INTO transcripts_fts(id, title, text, summary, speaker_names, source_url)
            VALUES(?,?,?,?,?,?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        let segmentText = record.segments.map(\.text).joined(separator: "\n")
        let fullSearchText = segmentText.isEmpty ? record.text : "\(record.text)\n\(segmentText)"
        sqlite3_bind_text(stmt, 1, record.id.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, record.title, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, fullSearchText, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, record.summary, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 5, record.speakerNames.joined(separator: " "), -1, sqliteTransient)
        sqlite3_bind_text(stmt, 6, record.sourceURL ?? "", -1, sqliteTransient)
        sqlite3_step(stmt)
    }

    private func fetchAll(kind: TranscriptRecordKind?, limit: Int, offset: Int = 0) -> [TranscriptRecord] {
        guard let db else { return [] }
        let kindClause = kind == nil ? "" : "WHERE kind = ? "
        let sql = """
            SELECT \(Self.columns)
            FROM transcripts
            \(kindClause)ORDER BY created_at DESC
            LIMIT ? OFFSET ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        var bind: Int32 = 1
        if let kind {
            sqlite3_bind_text(stmt, bind, kind.rawValue, -1, sqliteTransient)
            bind += 1
        }
        sqlite3_bind_int(stmt, bind, Int32(max(1, limit)))
        sqlite3_bind_int(stmt, bind + 1, Int32(max(0, offset)))
        return Self.readRows(stmt)
    }

    private func likeSearch(query: String, kind: TranscriptRecordKind?, limit: Int) -> [TranscriptRecord] {
        guard let db else { return [] }
        let pattern = "%\(query)%"
        let kindClause = kind == nil ? "" : " AND kind = ?"
        let sql = """
            SELECT \(Self.columns)
            FROM transcripts
            WHERE (title LIKE ? OR text LIKE ? OR summary LIKE ? OR segments_json LIKE ?)\(kindClause)
            ORDER BY created_at DESC
            LIMIT ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, pattern, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, pattern, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, pattern, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, pattern, -1, sqliteTransient)
        var bind: Int32 = 5
        if let kind {
            sqlite3_bind_text(stmt, bind, kind.rawValue, -1, sqliteTransient)
            bind += 1
        }
        sqlite3_bind_int(stmt, bind, Int32(max(1, limit)))
        return Self.readRows(stmt)
    }

    private func hasMigrationFlag(_ key: String) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM transcripts_meta WHERE key = ? LIMIT 1;", -1, &stmt, nil)
            == SQLITE_OK, let stmt else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func setMigrationFlag(_ key: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO transcripts_meta(key, value) VALUES(?, '1');", -1, &stmt, nil)
            == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)
        sqlite3_step(stmt)
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func deleteSQL(_ db: OpaquePointer, sql: String, id: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, sqliteTransient)
        sqlite3_step(stmt)
    }

    private func bindOptionalText(_ stmt: OpaquePointer, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static let columns = """
        id, kind, title, created_at, duration, text, raw_text, summary,
        action_items_json, decisions_json, segments_json, source_url,
        audio_filename, app_name, app_bundle_id, model_id, word_count, updated_at
        """

    private static let aliasedColumns = """
        t.id, t.kind, t.title, t.created_at, t.duration, t.text, t.raw_text, t.summary,
        t.action_items_json, t.decisions_json, t.segments_json, t.source_url,
        t.audio_filename, t.app_name, t.app_bundle_id, t.model_id, t.word_count, t.updated_at
        """

    private static func readRows(_ stmt: OpaquePointer) -> [TranscriptRecord] {
        var rows = [TranscriptRecord]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = decodeRow(stmt) { rows.append(item) }
        }
        return rows
    }

    private static func decodeRow(_ stmt: OpaquePointer) -> TranscriptRecord? {
        guard let id = UUID(uuidString: string(stmt, 0)) else { return nil }
        let kind = TranscriptRecordKind(rawValue: string(stmt, 1)) ?? .dictation
        let title = string(stmt, 2)
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let duration = sqlite3_column_double(stmt, 4)
        let text = string(stmt, 5)
        let rawText = string(stmt, 6)
        let summary = string(stmt, 7)
        let decoder = JSONDecoder()
        let actions = (try? decoder.decode([String].self, from: Data(string(stmt, 8).utf8))) ?? []
        let decisions = (try? decoder.decode([String].self, from: Data(string(stmt, 9).utf8))) ?? []
        let segments = (try? decoder.decode([TranscriptSegment].self, from: Data(string(stmt, 10).utf8))) ?? []
        return TranscriptRecord(
            id: id,
            kind: kind,
            title: title,
            createdAt: createdAt,
            duration: duration,
            text: text,
            rawText: rawText,
            summary: summary,
            actionItems: actions,
            decisions: decisions,
            segments: segments,
            sourceURL: optionalString(stmt, 11),
            audioFilename: optionalString(stmt, 12),
            appName: optionalString(stmt, 13),
            appBundleID: optionalString(stmt, 14),
            modelID: optionalString(stmt, 15),
            wordCount: Int(sqlite3_column_int(stmt, 16)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 17))
        )
    }

    private static func string(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    private static func optionalString(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        let value = String(cString: c)
        return value.isEmpty ? nil : value
    }

    private static func buildFTSQuery(_ query: String) -> String? {
        let tokens = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }
}
