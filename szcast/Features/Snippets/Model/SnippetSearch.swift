import Foundation

enum SnippetSearch {
    struct MatchResult: Sendable {
        let record: StoredSnippet
        let score: Int
    }

    struct Query: Sendable {
        let raw: String
        let normalized: String
        let terms: [String]
        let isSingleTerm: Bool
        var isEmpty: Bool { normalized.isEmpty }

        init(_ raw: String) {
            self.raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            self.normalized = FuzzyMatch.normalized(self.raw)
            self.terms = self.raw.split(whereSeparator: \Character.isWhitespace).map(String.init)
            self.isSingleTerm = terms.count <= 1
        }
    }

    /// Extracts a single-line clean excerpt from snippet body for list row previews.
    static func excerpt(for text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        return first.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Ranks a collection of stored snippets against a search query.
    /// Pinned items remain in the pinned section, sorted by relevance within pinned;
    /// unpinned items are sorted by relevance within unpinned.
    static func rank(_ records: [StoredSnippet], for rawQuery: String) -> [StoredSnippet] {
        let query = Query(rawQuery)
        guard !query.isEmpty else { return records }

        let scored: [MatchResult] = records.compactMap { record in
            guard let score = scoreSnippet(record.snippet, for: query) else { return nil }
            return MatchResult(record: record, score: score)
        }

        let sorted = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.record.snippet.name.count != rhs.record.snippet.name.count {
                return lhs.record.snippet.name.count < rhs.record.snippet.name.count
            }
            return lhs.record.snippet.name.localizedCaseInsensitiveCompare(rhs.record.snippet.name) == .orderedAscending
        }

        let pinned = sorted.filter { $0.record.snippet.isPinned }.map(\.record)
        let unpinned = sorted.filter { !$0.record.snippet.isPinned }.map(\.record)
        return pinned + unpinned
    }

    /// Computes a relevance score for a snippet against a query without fuzzy matching.
    /// Matches strictly via exact substring, prefix, word boundary, or full phrase matches.
    /// Non-contiguous fuzzy subsequence matching is strictly rejected.
    static func scoreSnippet(_ snippet: Snippet, for query: Query) -> Int? {
        guard !query.isEmpty else { return 0 }

        // 1. Direct match against snippet name (exact, prefix, wordStart, substring - no fuzzy subsequence)
        if let nameMatch = matchSubstring(query: query.raw, in: snippet.name) {
            return 2_000_000 + nameMatch
        }

        // 2. Direct match against snippet keyword
        if let keyword = snippet.keyword, !keyword.isEmpty,
           let kwMatch = matchSubstring(query: query.raw, in: keyword) {
            return 1_900_000 + kwMatch
        }

        // 3. Exact full query contained in snippet content body
        if let contentMatch = matchBody(query: query.raw, in: snippet.text) {
            return 1_500_000 + contentMatch
        }

        // 4. Direct match against snippet folder
        if let folder = snippet.folder, !folder.isEmpty,
           let folderMatch = matchSubstring(query: query.raw, in: folder) {
            return 1_200_000 + folderMatch
        }

        // 5. Multi-term matching: all terms must match as substrings somewhere in the snippet
        if !query.isSingleTerm {
            if let multiScore = scoreMultiTerm(snippet, terms: query.terms) {
                return multiScore
            }
        }

        return nil
    }

    /// Matches a query term against a string target strictly via exact, prefix, wordStart, or substring.
    /// Rejects any non-contiguous / fuzzy subsequence matching.
    static func matchSubstring(query: String, in target: String) -> Int? {
        guard let match = FuzzyMatch.match(query: query, candidate: target),
              match.tier != .subsequence else {
            return nil
        }
        switch match.tier {
        case .exact: return 500_000
        case .prefix: return 400_000 + match.score
        case .wordStart: return 300_000 + match.score
        case .substring: return 200_000 + match.score
        case .subsequence: return nil
        }
    }

    /// Checks if a query is contained as an exact substring in snippet body text,
    /// returning a score boosted by word-boundary placement and penalized by excessive length.
    static func matchBody(query: String, in text: String) -> Int? {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let atBoundary = range.lowerBound == text.startIndex
            || text[text.index(before: range.lowerBound)].isWhitespace
            || !text[text.index(before: range.lowerBound)].isLetter
        let lengthDamp = min(text.count / 30, 40_000)
        let boundaryBonus = atBoundary ? 50_000 : 0
        return 100_000 + boundaryBonus - lengthDamp
    }

    /// Evaluates multi-term queries where every term must match as an exact substring somewhere in the snippet.
    private static func scoreMultiTerm(_ snippet: Snippet, terms: [String]) -> Int? {
        var totalScore = 0
        var nameHits = 0
        var keywordHits = 0
        var contentHits = 0
        var folderHits = 0

        for term in terms {
            var matchedTerm = false
            var bestTermScore = 0

            // Try name
            if let nameScore = matchSubstring(query: term, in: snippet.name) {
                matchedTerm = true
                nameHits += 1
                bestTermScore = max(bestTermScore, nameScore + 50_000)
            }

            // Try keyword
            if let keyword = snippet.keyword, !keyword.isEmpty,
               let kwScore = matchSubstring(query: term, in: keyword) {
                matchedTerm = true
                keywordHits += 1
                bestTermScore = max(bestTermScore, kwScore + 40_000)
            }

            // Try content body substring
            if let bodyScore = matchBody(query: term, in: snippet.text) {
                matchedTerm = true
                contentHits += 1
                bestTermScore = max(bestTermScore, bodyScore + 20_000)
            }

            // Try folder
            if let folder = snippet.folder, !folder.isEmpty,
               let folderScore = matchSubstring(query: term, in: folder) {
                matchedTerm = true
                folderHits += 1
                bestTermScore = max(bestTermScore, folderScore + 10_000)
            }

            guard matchedTerm else { return nil }
            totalScore += bestTermScore
        }

        let band: Int
        if nameHits == terms.count {
            band = 1_800_000
        } else if nameHits > 0 && keywordHits > 0 {
            band = 1_600_000
        } else if nameHits > 0 && contentHits > 0 {
            band = 1_400_000
        } else if keywordHits > 0 && contentHits > 0 {
            band = 1_300_000
        } else if contentHits == terms.count {
            band = 1_100_000
        } else if contentHits > 0 {
            band = 1_000_000
        } else {
            band = 800_000
        }

        return band + totalScore
    }

    /// Extracts non-empty lines trimmed for inspection.
    static func extractLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Extracts rich tokens from text.
    static func extractContentTokens(_ text: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func add(_ s: String) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { return }
            let lower = trimmed.lowercased()
            if seen.insert(lower).inserted {
                result.append(lower)
            }
        }

        let whitespaceTokens = text.split(whereSeparator: \Character.isWhitespace)
        for token in whitespaceTokens {
            add(String(token))
            if seen.count >= 600 { break }
        }

        let components = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for comp in components {
            add(comp)
            if seen.count >= 600 { break }
        }

        return result
    }

    /// Backward-compatible alias for existing callers/tests.
    static func extractContentWords(_ text: String) -> [String] {
        extractContentTokens(text)
    }
}
