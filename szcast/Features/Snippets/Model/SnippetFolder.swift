import Foundation

enum SnippetFolderPath {
    static let maxDepth = 3

    /// Normalizes a user-supplied folder path, returning nil for empty or invalid paths.
    static func validated(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !parts.isEmpty, parts.count <= maxDepth else { return nil }
        for part in parts {
            guard isValidComponent(part) else { return nil }
        }
        return parts.joined(separator: "/")
    }

    /// Sanitizes an arbitrary imported group name into a valid folder path within `maxDepth`.
    static func sanitized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parts = raw
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: ":", with: "-")
            .split(separator: "/")
            .map { part -> String in
                var cleaned = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                while cleaned.hasPrefix(".") { cleaned.removeFirst() }
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        guard !parts.isEmpty else { return nil }
        return Array(parts.prefix(maxDepth)).joined(separator: "/")
    }

    static func isValidComponent(_ component: String) -> Bool {
        guard !component.isEmpty,
            component != ".",
            component != "..",
            !component.hasPrefix("."),
            !component.contains("/"),
            !component.contains("\\"),
            !component.contains(":"),
            !component.contains("\0")
        else { return false }
        return true
    }

    static func components(of path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    static func name(of path: String) -> String {
        components(of: path).last ?? path
    }

    static func parent(of path: String) -> String? {
        let parts = components(of: path)
        guard parts.count > 1 else { return nil }
        return parts.dropLast().joined(separator: "/")
    }

    static func depth(of path: String) -> Int {
        components(of: path).count
    }

    static func ancestorPaths(of path: String) -> [String] {
        let parts = components(of: path)
        var result: [String] = []
        var current = ""
        for part in parts {
            current = current.isEmpty ? part : "\(current)/\(part)"
            result.append(current)
        }
        return result
    }

    static func childPath(parent: String?, name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidComponent(trimmed) else { return nil }
        let candidate = parent.map { "\($0)/\(trimmed)" } ?? trimmed
        return validated(candidate)
    }
}

struct SnippetFolderMetadata: Codable, Sendable, Hashable {
    static let fileName = ".szcast-folder.json"

    var isEnabled: Bool
    var keywordPrefix: String?
    var icon: String?

    init(isEnabled: Bool = true, keywordPrefix: String? = nil, icon: String? = nil) {
        self.isEnabled = isEnabled
        self.keywordPrefix = Self.normalized(keywordPrefix)
        self.icon = Self.normalized(icon)
    }

    var isDefault: Bool {
        isEnabled && normalizedPrefix == nil && normalizedIcon == nil
    }

    var normalizedPrefix: String? {
        Self.normalized(keywordPrefix)
    }

    var normalizedIcon: String? {
        Self.normalized(icon)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

struct SnippetFolder: Identifiable, Sendable, Hashable {
    let path: String
    var metadata: SnippetFolderMetadata

    var id: String { path }
    var name: String { SnippetFolderPath.name(of: path) }
    var parentPath: String? { SnippetFolderPath.parent(of: path) }
    var depth: Int { SnippetFolderPath.depth(of: path) }
    var isEnabled: Bool { metadata.isEnabled }
    var keywordPrefix: String? { metadata.normalizedPrefix }
    var icon: String? { metadata.normalizedIcon }

    init(path: String, metadata: SnippetFolderMetadata = SnippetFolderMetadata()) {
        self.path = path
        self.metadata = metadata
    }
}

enum SnippetFolderPolicy {
    static func foldersByPath(from folders: [SnippetFolder]) -> [String: SnippetFolder] {
        Dictionary(uniqueKeysWithValues: folders.map { ($0.path, $0) })
    }

    static func isFolderEffectivelyEnabled(
        _ path: String,
        foldersByPath: [String: SnippetFolder]
    ) -> Bool {
        for ancestor in SnippetFolderPath.ancestorPaths(of: path) {
            if let folder = foldersByPath[ancestor], !folder.isEnabled {
                return false
            }
        }
        return true
    }

    static func isSnippetEffectivelyEnabled(
        _ snippet: Snippet,
        foldersByPath: [String: SnippetFolder]
    ) -> Bool {
        guard snippet.isEnabled else { return false }
        guard let folder = snippet.folder, !folder.isEmpty else { return true }
        return isFolderEffectivelyEnabled(folder, foldersByPath: foldersByPath)
    }

    static func effectivePrefix(
        for folderPath: String?,
        foldersByPath: [String: SnippetFolder]
    ) -> String {
        guard let folderPath, !folderPath.isEmpty else { return "" }
        var combined = ""
        for ancestor in SnippetFolderPath.ancestorPaths(of: folderPath) {
            if let prefix = foldersByPath[ancestor]?.keywordPrefix {
                combined += prefix
            }
        }
        return combined
    }

    static func effectiveKeyword(
        for snippet: Snippet,
        foldersByPath: [String: SnippetFolder]
    ) -> String? {
        guard let raw = snippet.keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        let prefix = effectivePrefix(for: snippet.folder, foldersByPath: foldersByPath)
        return prefix + raw
    }

    static func contains(_ snippetFolder: String?, in folderPath: String) -> Bool {
        guard let snippetFolder else { return false }
        return snippetFolder == folderPath || snippetFolder.hasPrefix(folderPath + "/")
    }
}
