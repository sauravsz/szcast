import Foundation

@MainActor
@Observable
final class CustomEmojiKeywordStore {
    static let shared = CustomEmojiKeywordStore()

    private let fileURL: URL
    private(set) var customKeywords: [String: [String]] = [:]
    private(set) var revision: Int = 0

    init(fileURL: URL = AppPaths.applicationSupport().appendingPathComponent("emoji-custom-keywords.json")) {
        self.fileURL = fileURL
        load()
    }

    func keywords(for glyph: String) -> [String] {
        customKeywords[glyph] ?? []
    }

    func setKeywords(_ keywords: [String], for glyph: String) {
        guard !glyph.isEmpty else { return }
        let clean = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        if clean.isEmpty {
            customKeywords.removeValue(forKey: glyph)
        } else {
            customKeywords[glyph] = Array(NSOrderedSet(array: clean)).compactMap { $0 as? String }
        }
        persist()
    }

    func addKeyword(_ keyword: String, for glyph: String) {
        guard !glyph.isEmpty else { return }
        let clean = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return }

        var existing = customKeywords[glyph] ?? []
        if !existing.contains(clean) {
            existing.append(clean)
            customKeywords[glyph] = existing
            persist()
        }
    }

    func removeKeyword(_ keyword: String, for glyph: String) {
        guard !glyph.isEmpty else { return }
        let clean = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard var existing = customKeywords[glyph], let index = existing.firstIndex(of: clean) else { return }
        existing.remove(at: index)
        if existing.isEmpty {
            customKeywords.removeValue(forKey: glyph)
        } else {
            customKeywords[glyph] = existing
        }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return
        }
        customKeywords = decoded
    }

    private func persist() {
        revision &+= 1
        do {
            let data = try JSONEncoder().encode(customKeywords)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Fail silent or write error
        }
    }
}
