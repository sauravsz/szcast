import Foundation

@MainActor
final class InlineEmojiCompletionService {
    static let shared = InlineEmojiCompletionService()

    struct Suggestion: Identifiable, Sendable {
        let glyph: String
        let name: String
        let query: String
        var id: String { glyph }
    }

    /// Detects if cursor is after a colon token like `:smile` (up to 30 characters).
    func detectTrigger(in text: String, cursorLocation: Int) -> (token: String, range: NSRange)? {
        guard cursorLocation > 0 else { return nil }
        let nsText = text as NSString
        guard cursorLocation <= nsText.length else { return nil }

        // Find last colon before cursor
        let colonRange = nsText.range(of: ":", options: .backwards, range: NSRange(location: 0, length: cursorLocation))
        guard colonRange.location != NSNotFound else { return nil }
        let tokenStart = colonRange.location

        // Ensure colon is either at start of text or preceded by whitespace / newline
        if tokenStart > 0 {
            let prevChar = nsText.substring(with: NSRange(location: tokenStart - 1, length: 1))
            guard prevChar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
        }

        let tokenLength = cursorLocation - tokenStart
        guard tokenLength >= 2, tokenLength <= 30 else { return nil } // at least ":x"

        let candidate = nsText.substring(with: NSRange(location: tokenStart + 1, length: tokenLength - 1))
        // Candidate should not contain whitespace or newlines
        guard !candidate.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }

        return (token: candidate, range: NSRange(location: tokenStart, length: tokenLength))
    }

    /// Suggestions ordered by pinned, frecency, and keyword/name relevance
    func suggestions(
        for token: String,
        index: EmojiIndex,
        frequent: FrequentEmojiStore,
        pinned: PinnedEmojiStore,
        tone: EmojiSkinTone,
        limit: Int = 8
    ) -> [Suggestion] {
        let results = index.search(token, frequent: frequent, limit: limit * 2)
        let pinnedGlyphs = Set(pinned.glyphs)

        // Sort pinned first, then direct search results
        let sorted = results.sorted { a, b in
            let aPin = pinnedGlyphs.contains(a.glyph)
            let bPin = pinnedGlyphs.contains(b.glyph)
            if aPin != bPin { return aPin }
            return false
        }

        return sorted.prefix(limit).map { entry in
            Suggestion(glyph: entry.display(tone: tone), name: entry.displayName, query: token)
        }
    }
}
