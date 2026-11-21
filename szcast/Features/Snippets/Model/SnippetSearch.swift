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

    /// Computes a relevance score for a snippet against a query, or returns nil if it doesn't match.
    static func scoreSnippet(_ snippet: Snippet, for query: Query) -> Int? {
        guard !query.isEmpty else { return 0 }

        // 1. Direct match against snippet name (highest priority)
        if let nameMatch = FuzzyMatch.match(query: query.raw, candidate: snippet.name) {
            let baseScore: Int
            switch nameMatch.tier {
            case .exact: baseScore = 3_000_000
            case .prefix: baseScore = 2_600_000
            case .wordStart: baseScore = 2_300_000
            case .substring: baseScore = 2_000_000
            case .subsequence: baseScore = 1_600_000
            }
            return baseScore + nameMatch.score
        }

        // 2. Direct match against snippet keyword
        if let keyword = snippet.keyword, !keyword.isEmpty,
           let kwMatch = FuzzyMatch.match(query: query.raw, candidate: keyword) {
            let baseScore: Int
            switch kwMatch.tier {
            case .exact: baseScore = 2_900_000
            case .prefix: baseScore = 2_500_000
            case .wordStart: baseScore = 2_200_000
            case .substring: baseScore = 1_900_000
            case .subsequence: baseScore = 1_500_000
            }
            return baseScore + kwMatch.score
        }

        // 3. Exact full query contained in snippet content body
        if snippet.text.range(of: query.raw, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            let lengthDamp = min(snippet.text.count / 20, 50_000)
            return 1_400_000 - lengthDamp
        }

        // 4. Direct match against snippet folder
        if let folder = snippet.folder, !folder.isEmpty,
           let folderMatch = FuzzyMatch.match(query: query.raw, candidate: folder) {
            let baseScore: Int
            switch folderMatch.tier {
            case .exact: baseScore = 1_300_000
            case .prefix: baseScore = 1_200_000
            case .wordStart: baseScore = 1_100_000
            case .substring: baseScore = 1_000_000
            case .subsequence: baseScore = 900_000
            }
            return baseScore + folderMatch.score
        }

        // 5. Multi-term matching: all terms must match across name, keyword, folder, or content body
        if !query.isSingleTerm {
            return scoreMultiTerm(snippet, terms: query.terms)
        }

        // 6. Single term fuzzy match against words in snippet content body
        return scoreContentFuzzy(snippet.text, term: query.raw)
    }

    /// Evaluates multi-term queries where every term must match somewhere in the snippet.
    private static func scoreMultiTerm(_ snippet: Snippet, terms: [String]) -> Int? {
        var totalScore = 0
        var nameHits = 0
        var keywordHits = 0
        var contentHits = 0
        var folderHits = 0

        let contentWords = extractContentWords(snippet.text)

        for term in terms {
            var matchedTerm = false
            var bestTermScore = 0

            // Try name
            if let match = FuzzyMatch.match(query: term, candidate: snippet.name) {
                matchedTerm = true
                nameHits += 1
                bestTermScore = max(bestTermScore, match.score + (match.tier == .exact ? 50_000 : 20_000))
            }

            // Try keyword
            if let keyword = snippet.keyword, !keyword.isEmpty,
               let match = FuzzyMatch.match(query: term, candidate: keyword) {
                matchedTerm = true
                keywordHits += 1
                bestTermScore = max(bestTermScore, match.score + (match.tier == .exact ? 40_000 : 15_000))
            }

            // Try content substring
            if snippet.text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                matchedTerm = true
                contentHits += 1
                bestTermScore = max(bestTermScore, 10_000)
            } else if let wordScore = matchAnyWord(in: contentWords, term: term) {
                matchedTerm = true
                contentHits += 1
                bestTermScore = max(bestTermScore, wordScore)
            }

            // Try folder
            if let folder = snippet.folder, !folder.isEmpty,
               let match = FuzzyMatch.match(query: term, candidate: folder) {
                matchedTerm = true
                folderHits += 1
                bestTermScore = max(bestTermScore, match.score + 5_000)
            }

            guard matchedTerm else { return nil }
            totalScore += bestTermScore
        }

        let band: Int
        if nameHits == terms.count {
            band = 2_200_000
        } else if nameHits > 0 && keywordHits > 0 {
            band = 2_000_000
        } else if nameHits > 0 {
            band = 1_800_000
        } else if keywordHits > 0 {
            band = 1_600_000
        } else if contentHits > 0 {
            band = 1_100_000
        } else {
            band = 800_000
        }

        return band + totalScore
    }

    /// Evaluates fuzzy matching against words in snippet content.
    private static func scoreContentFuzzy(_ text: String, term: String) -> Int? {
        guard term.count >= 2 else { return nil }
        let words = extractContentWords(text)
        guard let bestWordScore = matchAnyWord(in: words, term: term) else { return nil }
        return 700_000 + bestWordScore
    }

    /// Extracts distinct alphanumeric words from text for indexing and fuzzy matching.
    static func extractContentWords(_ text: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        let components = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for comp in components {
            let trimmed = comp.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2 {
                let lower = trimmed.lowercased()
                if seen.insert(lower).inserted {
                    result.append(lower)
                    if result.count >= 150 { break }
                }
            }
        }
        return result
    }

    private static func matchAnyWord(in words: [String], term: String) -> Int? {
        var best: Int?
        for word in words {
            if let match = FuzzyMatch.match(query: term, candidate: word) {
                switch match.tier {
                case .exact:
                    best = max(best ?? 0, 15_000)
                case .prefix:
                    best = max(best ?? 0, 10_000 + match.score)
                case .wordStart:
                    best = max(best ?? 0, 8_000 + match.score)
                case .substring:
                    best = max(best ?? 0, 5_000 + match.score)
                case .subsequence:
                    if match.score >= 8 {
                        best = max(best ?? 0, match.score)
                    }
                }
            }
        }
        return best
    }
}
