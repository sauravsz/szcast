import Foundation

/// The user's per-entry aliases, keyed like favorites and ranking by `preferenceKey`.
@MainActor
@Observable
final class AliasStore {
    private let defaults: UserDefaults
    private let defaultsKey = "launcherAliases"

    private(set) var aliases: [String: String]
    /// AppIndex includes this in its result key, invalidating a ranking when an alias changes.
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aliases = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    func alias(for entryKey: String) -> String? { aliases[entryKey] }

    /// Returns the entry key whose alias matches the candidate (case-insensitive).
    func entryKey(forAlias candidate: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        for (key, val) in aliases {
            if val.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed {
                return key
            }
        }
        return nil
    }

    /// Set of all configured aliases (lowercased, trimmed).
    var allAliases: Set<String> {
        Set(aliases.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }

    /// Stored as typed — trimming here would eat the space mid-word — but blank still means none.
    func setAlias(_ alias: String, for entryKey: String) {
        let value = alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : alias
        guard aliases[entryKey] != value else { return }
        aliases[entryKey] = value
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }

    func removeKeys(_ keys: Set<String>) {
        let remaining = aliases.filter { !keys.contains($0.key) }
        guard remaining.count != aliases.count else { return }
        aliases = remaining
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }

    func replace(_ new: [String: String]) {
        // An import obeys the same rule as typing: blank means none, or it lands unclearable.
        aliases = new.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }
}

/// Detection and extraction of `<alias><Space>` triggers from a search query.
struct AliasTrigger: Sendable, Equatable {
    let alias: String
    let remainder: String

    /// Parses a query like "e " or "e heart" against configured aliases.
    /// Returns the matched alias and the trailing remainder query, if any.
    static func parse(_ query: String, registeredAliases: Set<String>) -> AliasTrigger? {
        guard !query.hasPrefix(" ") else { return nil }
        let lower = query.lowercased()
        // Sort descending by length so longer aliases match first if prefixes overlap
        for alias in registeredAliases.sorted(by: { $0.count > $1.count }) {
            if lower.hasPrefix(alias + " ") || lower == alias + " " {
                let dropCount = alias.count + 1
                let remainder = String(query.dropFirst(min(dropCount, query.count))).trimmingCharacters(in: .whitespaces)
                return AliasTrigger(alias: alias, remainder: remainder)
            }
        }
        return nil
    }
}
