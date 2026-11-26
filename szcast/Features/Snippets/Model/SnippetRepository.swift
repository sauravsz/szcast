import Foundation

struct SnippetRepository: Sendable {
    /// Holds no state beyond the `NSLock` every access already goes through.
    private final class DirectoryLock: @unchecked Sendable {
        private let lock = NSLock()

        func withLock<Value>(
            _ operation: () throws(RepositoryError) -> Value
        ) throws(RepositoryError) -> Value {
            lock.lock()
            defer { lock.unlock() }
            return try operation()
        }
    }

    /// `locks` is only ever read or written inside `lock.withLock`, which is the whole guarantee.
    private final class DirectoryLockTable: @unchecked Sendable {
        private let lock = NSLock()
        private var locks: [String: DirectoryLock] = [:]

        func directoryLock(for directory: URL) -> DirectoryLock {
            let identity = canonicalIdentity(for: directory)
            return lock.withLock {
                if let existing = locks[identity] { return existing }
                let directoryLock = DirectoryLock()
                locks[identity] = directoryLock
                return directoryLock
            }
        }

        private func canonicalIdentity(for directory: URL) -> String {
            let fileManager = FileManager.default
            var existingAncestor = directory.standardizedFileURL
            var missingComponents: [String] = []

            while !fileManager.fileExists(atPath: existingAncestor.path) {
                let parent = existingAncestor.deletingLastPathComponent()
                guard parent.path != existingAncestor.path else { break }
                missingComponents.append(existingAncestor.lastPathComponent)
                existingAncestor = parent
            }

            var resolved = existingAncestor.resolvingSymlinksInPath().standardizedFileURL
            for component in missingComponents.reversed() {
                resolved.appendPathComponent(component, isDirectory: true)
            }
            return resolved.standardizedFileURL.path
        }
    }

    private static let directoryLocks = DirectoryLockTable()

    enum Mutation: Sendable {
        case save
        case delete
    }

    struct MutationHooks: Sendable {
        var beforeRevalidation: @Sendable (Mutation, URL) -> Void = { _, _ in }
    }

    struct Snapshot: Sendable, Equatable {
        let records: [StoredSnippet]
        let folders: [SnippetFolder]
        let issues: [Issue]

        init(records: [StoredSnippet], folders: [SnippetFolder] = [], issues: [Issue]) {
            self.records = records
            self.folders = folders
            self.issues = issues
        }

        /// Every file still on disk: one that fails to parse is mid-edit, not deleted.
        var fileIDs: Set<StoredSnippet.ID> { Set(records.map(\.id) + issues.map(\.id)) }
    }

    struct Issue: Identifiable, Sendable, Equatable {
        let fileURL: URL
        let message: String

        var id: String { fileURL.standardizedFileURL.path }
    }

    enum RepositoryError: Error, LocalizedError, Sendable, Equatable {
        case conflict(
            fileURL: URL,
            expected: SnippetSourceRevision,
            actual: SnippetSourceRevision?
        )
        case fileNotFound(URL)
        case invalidFileLocation(URL)
        case invalidFolderPath(String)
        case folderAlreadyExists(String)
        case folderNotFound(String)
        case io(fileURL: URL, message: String)

        var errorDescription: String? {
            switch self {
            case .conflict(let fileURL, _, _):
                return String(
                    localized: """
                        The snippet changed on disk. Reload it before saving or deleting. \
                        (\(fileURL.lastPathComponent))
                        """)
            case .fileNotFound(let fileURL):
                return String(localized: "The snippet file no longer exists. (\(fileURL.lastPathComponent))")
            case .invalidFileLocation(let fileURL):
                return String(
                    localized: "The snippet file is outside this szcast channel. (\(fileURL.path))")
            case .invalidFolderPath(let path):
                return String(
                    localized: "The snippet folder path “\(path)” is invalid or deeper than 3 levels.")
            case .folderAlreadyExists(let path):
                return String(localized: "A snippet folder named “\(path)” already exists.")
            case .folderNotFound(let path):
                return String(localized: "The snippet folder “\(path)” no longer exists.")
            case .io(let fileURL, let message):
                return String(localized: "Could not access \(fileURL.path): \(message)")
            }
        }
    }

    let bundleIdentifier: String
    let channelDirectory: URL
    let snippetsDirectory: URL

    private let directoryLock: DirectoryLock
    private let mutationHooks: MutationHooks

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.sauravsz.szcast",
        applicationSupportRoot: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0],
        snippetsDirectory: URL? = nil,
        mutationHooks: MutationHooks = MutationHooks()
    ) {
        self.bundleIdentifier = bundleIdentifier
        let channelDirectory = applicationSupportRoot.appendingPathComponent(
            bundleIdentifier,
            isDirectory: true)
        self.channelDirectory = channelDirectory
        let snippetsDirectory =
            snippetsDirectory ?? channelDirectory.appendingPathComponent("Snippets", isDirectory: true)
        self.snippetsDirectory = snippetsDirectory
        directoryLock = Self.directoryLocks.directoryLock(for: snippetsDirectory)
        self.mutationHooks = mutationHooks
    }

    func load() throws(RepositoryError) -> Snapshot {
        try directoryLock.withLock { () throws(RepositoryError) -> Snapshot in
            try mappedError(at: snippetsDirectory) {
                try ensureSnippetsDirectory()
                let crawled = try crawlTree(in: snippetsDirectory)
                var records: [StoredSnippet] = []
                var issues: [Issue] = []

                for entry in crawled.files {
                    do {
                        let content = try String(contentsOf: entry.url, encoding: .utf8)
                        var snippet = try SnippetMarkdownSerializer.parse(
                            content: content,
                            fileURL: entry.url)
                        if let folderPath = entry.folderPath {
                            snippet.folder = folderPath
                        } else if let frontmatterFolder = snippet.folder {
                            snippet.folder = SnippetFolderPath.validated(frontmatterFolder)
                        }
                        records.append(
                            StoredSnippet(
                                fileURL: entry.url,
                                snippet: snippet,
                                sourceRevision: SnippetSourceRevision(content: content)))
                    } catch {
                        issues.append(Issue(fileURL: entry.url, message: error.localizedDescription))
                    }
                }

                records.sort(by: recordOrder)
                issues.sort { $0.fileURL.path < $1.fileURL.path }
                let folders = crawled.folders.sorted {
                    $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
                }
                return Snapshot(records: records, folders: folders, issues: issues)
            }
        }
    }

    func create(_ snippet: Snippet) throws(RepositoryError) -> StoredSnippet {
        try directoryLock.withLock { () throws(RepositoryError) -> StoredSnippet in
            try mappedError(at: snippetsDirectory) {
                try ensureSnippetsDirectory()
                return try createUnlocked(snippet)
            }
        }
    }

    func create(_ snippets: [Snippet]) throws(RepositoryError) -> [StoredSnippet] {
        try directoryLock.withLock { () throws(RepositoryError) -> [StoredSnippet] in
            try mappedError(at: snippetsDirectory) {
                try ensureSnippetsDirectory()
                var created: [StoredSnippet] = []
                do {
                    for snippet in snippets {
                        created.append(try createUnlocked(snippet))
                    }
                    return created
                } catch {
                    for record in created.reversed() {
                        try? FileManager.default.removeItem(at: record.fileURL)
                    }
                    throw error
                }
            }
        }
    }

    func save(
        _ snippet: Snippet,
        fileURL: URL,
        expectedRevision: SnippetSourceRevision
    ) throws(RepositoryError) -> StoredSnippet {
        try directoryLock.withLock { () throws(RepositoryError) -> StoredSnippet in
            try mappedError(at: fileURL) {
                let fileURL = try validatedFileURL(fileURL)
                let resolvedFolder = try validatedTargetFolder(snippet.folder)
                let targetDirectory = directoryURL(forFolderPath: resolvedFolder)
                let currentDirectory = fileURL.deletingLastPathComponent().standardizedFileURL

                var normalizedSnippet = snippet
                normalizedSnippet.folder = resolvedFolder
                var diskSnippet = normalizedSnippet
                // Directory is the source of truth when stored inside a subfolder.
                if resolvedFolder != nil { diskSnippet.folder = nil }
                let content = SnippetMarkdownSerializer.serialize(diskSnippet)

                if targetDirectory.standardizedFileURL.resolvingSymlinksInPath().path
                    == currentDirectory.resolvingSymlinksInPath().path
                {
                    return try coordinatedMutation(at: fileURL, options: .forReplacing) { coordinatedURL in
                        mutationHooks.beforeRevalidation(.save, coordinatedURL)
                        let mutationURL = try validatedFileURL(coordinatedURL)
                        let actualRevision = try revision(at: mutationURL)
                        guard actualRevision == expectedRevision else {
                            throw RepositoryError.conflict(
                                fileURL: fileURL,
                                expected: expectedRevision,
                                actual: actualRevision)
                        }
                        try Data(content.utf8).write(to: mutationURL, options: .atomic)
                        return StoredSnippet(
                            fileURL: fileURL,
                            snippet: normalizedSnippet,
                            sourceRevision: SnippetSourceRevision(content: content))
                    }
                }

                try FileManager.default.createDirectory(
                    at: targetDirectory, withIntermediateDirectories: true)
                return try coordinatedMutation(at: fileURL, options: .forDeleting) { coordinatedURL in
                    mutationHooks.beforeRevalidation(.save, coordinatedURL)
                    let mutationURL = try validatedFileURL(coordinatedURL)
                    let actualRevision = try revision(at: mutationURL)
                    guard actualRevision == expectedRevision else {
                        throw RepositoryError.conflict(
                            fileURL: fileURL,
                            expected: expectedRevision,
                            actual: actualRevision)
                    }
                    let destinationURL = try writeMovedSnippet(
                        Data(content.utf8),
                        preferredFilename: fileURL.lastPathComponent,
                        snippetName: normalizedSnippet.name,
                        in: targetDirectory)
                    try FileManager.default.removeItem(at: mutationURL)
                    return StoredSnippet(
                        fileURL: destinationURL,
                        snippet: normalizedSnippet,
                        sourceRevision: SnippetSourceRevision(content: content))
                }
            }
        }
    }

    func createFolder(
        path rawPath: String,
        metadata: SnippetFolderMetadata = SnippetFolderMetadata()
    ) throws(RepositoryError) -> SnippetFolder {
        try directoryLock.withLock { () throws(RepositoryError) -> SnippetFolder in
            try mappedError(at: snippetsDirectory) {
                try ensureSnippetsDirectory()
                guard let path = SnippetFolderPath.validated(rawPath) else {
                    throw RepositoryError.invalidFolderPath(rawPath)
                }
                let folderURL = directoryURL(forFolderPath: path)
                if FileManager.default.fileExists(atPath: folderURL.path) {
                    throw RepositoryError.folderAlreadyExists(path)
                }
                try FileManager.default.createDirectory(
                    at: folderURL, withIntermediateDirectories: true)
                try writeMetadata(metadata, in: folderURL)
                return SnippetFolder(path: path, metadata: metadata)
            }
        }
    }

    func updateFolderMetadata(
        _ metadata: SnippetFolderMetadata,
        at rawPath: String
    ) throws(RepositoryError) -> SnippetFolder {
        try directoryLock.withLock { () throws(RepositoryError) -> SnippetFolder in
            try mappedError(at: snippetsDirectory) {
                guard let path = SnippetFolderPath.validated(rawPath) else {
                    throw RepositoryError.invalidFolderPath(rawPath)
                }
                let folderURL = directoryURL(forFolderPath: path)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir),
                    isDir.boolValue
                else {
                    throw RepositoryError.folderNotFound(path)
                }
                try writeMetadata(metadata, in: folderURL)
                return SnippetFolder(path: path, metadata: metadata)
            }
        }
    }

    func renameFolder(
        from rawOldPath: String,
        to rawNewPath: String
    ) throws(RepositoryError) -> (
        folder: SnippetFolder,
        movedIDs: [(oldID: StoredSnippet.ID, newID: StoredSnippet.ID)]
    ) {
        try directoryLock.withLock { () throws(RepositoryError) in
            try mappedError(at: snippetsDirectory) {
                guard let oldPath = SnippetFolderPath.validated(rawOldPath) else {
                    throw RepositoryError.invalidFolderPath(rawOldPath)
                }
                guard let newPath = SnippetFolderPath.validated(rawNewPath) else {
                    throw RepositoryError.invalidFolderPath(rawNewPath)
                }
                let oldURL = directoryURL(forFolderPath: oldPath)
                let newURL = directoryURL(forFolderPath: newPath)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: oldURL.path, isDirectory: &isDir),
                    isDir.boolValue
                else {
                    throw RepositoryError.folderNotFound(oldPath)
                }
                if oldPath == newPath {
                    let meta = loadMetadata(in: oldURL)
                    return (SnippetFolder(path: newPath, metadata: meta), [])
                }
                if SnippetFolderPath.ancestorPaths(of: newPath).contains(oldPath) {
                    throw RepositoryError.invalidFolderPath(newPath)
                }
                if FileManager.default.fileExists(atPath: newURL.path) {
                    throw RepositoryError.folderAlreadyExists(newPath)
                }
                let maxSubtreeDepth = maxRelativeSubfolderDepth(in: oldURL)
                if SnippetFolderPath.depth(of: newPath) + maxSubtreeDepth > SnippetFolderPath.maxDepth {
                    throw RepositoryError.invalidFolderPath(newPath)
                }

                let existingSnippets = collectMarkdownFilesRecursively(in: oldURL)
                let parentDir = newURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: oldURL, to: newURL)

                let oldStandardized = oldURL.standardizedFileURL.path
                let oldResolved = oldURL.standardizedFileURL.resolvingSymlinksInPath().path
                let newStandardized = newURL.standardizedFileURL.path
                let movedIDs: [(oldID: StoredSnippet.ID, newID: StoredSnippet.ID)] =
                    existingSnippets.map { fileURL in
                        let candidate = fileURL.standardizedFileURL.path
                    let suffix: String
                    if candidate.hasPrefix(oldStandardized) {
                        suffix = String(candidate.dropFirst(oldStandardized.count))
                    } else if candidate.hasPrefix(oldResolved) {
                        suffix = String(candidate.dropFirst(oldResolved.count))
                    } else {
                        suffix = "/" + fileURL.lastPathComponent
                    }
                    return (oldStandardized + suffix, newStandardized + suffix)
                }
                let metadata = loadMetadata(in: newURL)
                return (SnippetFolder(path: newPath, metadata: metadata), movedIDs)
            }
        }
    }

    func deleteFolder(at rawPath: String) throws(RepositoryError) -> [StoredSnippet.ID] {
        try directoryLock.withLock { () throws(RepositoryError) -> [StoredSnippet.ID] in
            try mappedError(at: snippetsDirectory) {
                guard let path = SnippetFolderPath.validated(rawPath) else {
                    throw RepositoryError.invalidFolderPath(rawPath)
                }
                let folderURL = directoryURL(forFolderPath: path)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir),
                    isDir.boolValue
                else {
                    throw RepositoryError.folderNotFound(path)
                }
                let removedIDs = collectMarkdownFilesRecursively(in: folderURL).map {
                    $0.standardizedFileURL.path
                }
                try FileManager.default.removeItem(at: folderURL)
                return removedIDs
            }
        }
    }

    func delete(
        fileURL: URL,
        expectedRevision: SnippetSourceRevision
    ) throws(RepositoryError) {
        try directoryLock.withLock { () throws(RepositoryError) in
            try mappedError(at: fileURL) {
                let fileURL = try validatedFileURL(fileURL)
                try coordinatedMutation(at: fileURL, options: .forDeleting) { coordinatedURL in
                    mutationHooks.beforeRevalidation(.delete, coordinatedURL)
                    let mutationURL = try validatedFileURL(coordinatedURL)
                    let actualRevision = try revision(at: mutationURL)
                    guard actualRevision == expectedRevision else {
                        throw RepositoryError.conflict(
                            fileURL: fileURL,
                            expected: expectedRevision,
                            actual: actualRevision)
                    }
                    try FileManager.default.removeItem(at: mutationURL)
                }
            }
        }
    }

    /// Only has to guarantee the folder exists; intermediates cover the channel directory too.
    private func ensureSnippetsDirectory() throws {
        try FileManager.default.createDirectory(
            at: snippetsDirectory, withIntermediateDirectories: true)
    }

    private struct CrawledFile {
        let url: URL
        let folderPath: String?
    }

    private struct CrawledTree {
        var files: [CrawledFile] = []
        var folders: [SnippetFolder] = []
    }

    private func crawlTree(in root: URL) throws -> CrawledTree {
        var tree = CrawledTree()
        var visitedDirs: Set<String> = [root.standardizedFileURL.resolvingSymlinksInPath().path]

        func walk(_ directory: URL, folderPath: String?, depth: Int) throws {
            let items = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for item in items {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    guard depth < SnippetFolderPath.maxDepth else { continue }
                    let component = item.lastPathComponent
                    guard SnippetFolderPath.isValidComponent(component) else { continue }
                    let canonicalDir = item.standardizedFileURL.resolvingSymlinksInPath().path
                    guard visitedDirs.insert(canonicalDir).inserted else { continue }
                    let childFolderPath = folderPath.map { "\($0)/\(component)" } ?? component
                    let metadata = loadMetadata(in: item)
                    tree.folders.append(SnippetFolder(path: childFolderPath, metadata: metadata))
                    try walk(item, folderPath: childFolderPath, depth: depth + 1)
                } else if item.pathExtension.lowercased() == "md", Self.isLoadableFile(item) {
                    tree.files.append(CrawledFile(url: item, folderPath: folderPath))
                }
            }
        }

        try walk(root, folderPath: nil, depth: 0)
        tree.files.sort { $0.url.path < $1.url.path }
        return tree
    }

    private func loadMetadata(in directory: URL) -> SnippetFolderMetadata {
        let metadataURL = directory.appendingPathComponent(SnippetFolderMetadata.fileName)
        guard let data = try? Data(contentsOf: metadataURL),
            let decoded = try? JSONDecoder().decode(SnippetFolderMetadata.self, from: data)
        else { return SnippetFolderMetadata() }
        return SnippetFolderMetadata(
            isEnabled: decoded.isEnabled,
            keywordPrefix: decoded.keywordPrefix,
            icon: decoded.icon)
    }

    private func writeMetadata(_ metadata: SnippetFolderMetadata, in directory: URL) throws {
        let metadataURL = directory.appendingPathComponent(SnippetFolderMetadata.fileName)
        if metadata.isDefault {
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                try FileManager.default.removeItem(at: metadataURL)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func validatedTargetFolder(_ raw: String?) throws -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let validated = SnippetFolderPath.validated(trimmed) else {
            throw RepositoryError.invalidFolderPath(raw)
        }
        return validated
    }

    private func directoryURL(forFolderPath folderPath: String?) -> URL {
        guard let folderPath else { return snippetsDirectory }
        var url = snippetsDirectory
        for component in SnippetFolderPath.components(of: folderPath) {
            url.appendPathComponent(component, isDirectory: true)
        }
        return url
    }

    private func collectMarkdownFilesRecursively(in directory: URL) -> [URL] {
        var urls: [URL] = []
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        for item in items {
            let child = directory.appendingPathComponent(item.lastPathComponent)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue {
                urls.append(contentsOf: collectMarkdownFilesRecursively(in: child))
            } else if child.pathExtension.lowercased() == "md", Self.isLoadableFile(child) {
                urls.append(child)
            }
        }
        return urls
    }

    private func maxRelativeSubfolderDepth(in directory: URL) -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var maxDepth = 0
        for item in items {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                maxDepth = max(maxDepth, 1 + maxRelativeSubfolderDepth(in: item))
            }
        }
        return maxDepth
    }

    // Keeps a directory or device node named `*.md` out; only non-files pay for resolving.
    private static func isLoadableFile(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return true }
        return
            (try? url.resolvingSymlinksInPath()
            .resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func createUnlocked(_ snippet: Snippet) throws -> StoredSnippet {
        let resolvedFolder = try validatedTargetFolder(snippet.folder)
        let targetDirectory = directoryURL(forFolderPath: resolvedFolder)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        var normalizedSnippet = snippet
        normalizedSnippet.folder = resolvedFolder
        var diskSnippet = normalizedSnippet
        if resolvedFolder != nil { diskSnippet.folder = nil }
        let content = SnippetMarkdownSerializer.serialize(diskSnippet)
        var suffix = 1

        while true {
            let fileURL = uniqueFileURL(
                for: normalizedSnippet.name,
                suffix: suffix,
                in: targetDirectory)
            do {
                try writeNewFileAtomically(Data(content.utf8), to: fileURL)
                return StoredSnippet(
                    fileURL: fileURL,
                    snippet: normalizedSnippet,
                    sourceRevision: SnippetSourceRevision(content: content))
            } catch {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    suffix += 1
                    continue
                }
                throw error
            }
        }
    }

    private func writeMovedSnippet(
        _ data: Data,
        preferredFilename: String,
        snippetName: String,
        in directory: URL
    ) throws -> URL {
        let preferredURL = directory.appendingPathComponent(preferredFilename)
        if !FileManager.default.fileExists(atPath: preferredURL.path) {
            do {
                try writeNewFileAtomically(data, to: preferredURL)
                return preferredURL
            } catch where FileManager.default.fileExists(atPath: preferredURL.path) {
            }
        }
        var suffix = 1
        while true {
            let fileURL = uniqueFileURL(for: snippetName, suffix: suffix, in: directory)
            do {
                try writeNewFileAtomically(data, to: fileURL)
                return fileURL
            } catch {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    suffix += 1
                    continue
                }
                throw error
            }
        }
    }

    private func writeNewFileAtomically(_ data: Data, to fileURL: URL) throws {
        let temporaryURL = fileURL.deletingLastPathComponent().appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func uniqueFileURL(for name: String, suffix: Int, in directory: URL) -> URL {
        let base = SnippetMarkdownSerializer.slug(for: name)
        let filename = suffix == 1 ? "\(base).md" : "\(base)-\(suffix).md"
        return directory.appendingPathComponent(filename)
    }

    private func validatedFileURL(_ fileURL: URL) throws -> URL {
        let standardized = fileURL.standardizedFileURL
        let parentPath = standardized.deletingLastPathComponent().resolvingSymlinksInPath().path
        let snippetsPath = snippetsDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard parentPath == snippetsPath || parentPath.hasPrefix(snippetsPath + "/"),
            standardized.pathExtension.lowercased() == "md"
        else {
            throw RepositoryError.invalidFileLocation(fileURL)
        }
        return standardized
    }

    private func revision(at fileURL: URL) throws -> SnippetSourceRevision {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RepositoryError.fileNotFound(fileURL)
        }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return SnippetSourceRevision(content: content)
    }

    private func recordOrder(_ lhs: StoredSnippet, _ rhs: StoredSnippet) -> Bool {
        let comparison = lhs.snippet.name.localizedCaseInsensitiveCompare(rhs.snippet.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id < rhs.id
    }

    private func coordinatedMutation<Value>(
        at fileURL: URL,
        options: NSFileCoordinator.WritingOptions,
        _ mutation: (URL) throws -> Value
    ) throws -> Value {
        let fileCoordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Value, Error>?
        fileCoordinator.coordinate(
            writingItemAt: fileURL,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try mutation(coordinatedURL) }
        }
        if let result { return try result.get() }
        if let coordinationError { throw coordinationError }
        throw CocoaError(.fileWriteUnknown)
    }

    private func mappedError<Value>(
        at fileURL: URL,
        _ operation: () throws -> Value
    ) throws(RepositoryError) -> Value {
        do {
            return try operation()
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw .io(fileURL: fileURL, message: error.localizedDescription)
        }
    }

}
