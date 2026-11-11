import Foundation
import OSLog

@MainActor
@Observable
final class DictationHistoryStore {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationHistory")
    private let fileURL: URL

    private(set) var items: [DictationHistoryItem] = []

    init(
        fileURL: URL = AppPaths.applicationSupport().appending(path: "dictation-history.json")
    ) {
        self.fileURL = fileURL
        load()
    }

    func add(text: String, rawText: String = "", duration: TimeInterval = 0) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let item = DictationHistoryItem(text: clean, rawText: rawText, duration: duration)
        items.insert(item, at: 0)
        // Keep latest 250 items
        if items.count > 250 {
            items = Array(items.prefix(250))
        }
        save()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }

    private func load() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                items = try JSONDecoder().decode([DictationHistoryItem].self, from: data)
                return
            } catch {
                Self.logger.error("Failed to load dictation history: \(error.localizedDescription)")
            }
        }
    }

    private func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save dictation history: \(error.localizedDescription)")
        }
    }
}
