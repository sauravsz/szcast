import Foundation

/// The one place an entry's searchable names are decided, for every kind alike.
enum EntryNaming {
    struct Sources: Sendable, Hashable {
        var name: String
        /// Ranked like the title: a translation, a renamed file, a snippet keyword.
        var alternateTitles: [String] = []
        /// What the entry comes from, shown beside it: an extension's title.
        var subtitle: String?
        /// Found by, never ranked by: a declared name, an extension's keywords.
        var keywords: [String] = []

        init(name: String) { self.name = name }
    }

    static func profile(for sources: Sources) -> SearchProfile {
        let title = SearchText(sources.name, transliterated: true)
        // Folded, never transliterated: these compare against the query as typed.
        let alternates = usable(sources.alternateTitles, rejecting: [sources.name])
            .map { SearchText($0, transliterated: false) }
        let subtitle = sources.subtitle
            .map { SearchText($0, transliterated: true) }
            .flatMap { $0.isEmpty || $0.units == title.units ? nil : $0 }
        var keywords = usable(sources.keywords, rejecting: [sources.name] + sources.alternateTitles)
            .map { SearchText($0, transliterated: true) }
        if let subtitle { keywords += [title.joined(with: subtitle), subtitle.joined(with: title)] }
        return SearchProfile(
            title: title, alternateTitles: alternates, subtitle: subtitle, keywords: keywords)
    }

    static func strippingAppExtension(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Info.plist lists repeat the name and ship `ALTERNATE_NAME_1` placeholders.
    static func usable(_ raw: [String], rejecting existing: [String]) -> [String] {
        var seen = Set(existing.map { FuzzyMatch.normalized(strippingAppExtension($0)) })
        return raw.compactMap { candidate in
            let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !isPlaceholder(name) else { return nil }
            let key = FuzzyMatch.normalized(strippingAppExtension(name))
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return name
        }
    }

    /// A lone SCREAMING_SNAKE token is an untranslated placeholder, and several ship.
    private static func isPlaceholder(_ name: String) -> Bool {
        name.contains("_") && !name.contains(where: { $0.isLowercase || $0.isWhitespace })
    }

    /// What is left of `query` once it has named an entry — the text the row was found by,
    /// which a screen the row opens may seed as its own search.
    ///
    /// Typing `search files report` and pressing Return opens file search holding `report`.
    /// Without this the screen opens holding the whole phrase, so its list filters to nothing.
    /// Only a leading name is stripped, and only as whole words.
    ///
    /// Nil means the query does not begin with a name: nothing was consumed, so the whole
    /// query stands. An empty string means the query *is* the name, which seeds nothing —
    /// and differs from nil at `PaletteCoordinator.togglePalette`, where nil would close
    /// an already-open screen instead of opening it blank.
    static func queryRemainder(_ query: String, names: [String]) -> String? {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        // Longest name first, so `Search Menu Bar Items` wins over `Search`, `Command` or `Item`.
        let candidates = names
            .map { $0.split(whereSeparator: \.isWhitespace) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for name in candidates {
            // Whole words only: a shorter run would let `Finder` eat `Finderer`.
            guard name.count <= words.count else { continue }
            let matches = zip(words, name).allSatisfy {
                FuzzyMatch.normalized(String($0)) == FuzzyMatch.normalized(String($1))
            }
            guard matches else { continue }
            return words.dropFirst(name.count).joined(separator: " ")
        }
        return nil
    }
}

/// Built by `EntryNaming.profile` alone.
struct SearchProfile: Sendable, Hashable {
    var title: SearchText
    var alternateTitles: [SearchText]
    var subtitle: SearchText?
    /// Match to appear, never to rank.
    var keywords: [SearchText]

    /// What an entry holds before its first index pass: nothing a query can reach.
    static let unnamed = SearchProfile(
        title: SearchText(units: []), alternateTitles: [], subtitle: nil, keywords: [])
}
