import Darwin
import Foundation

@MainActor
@Observable
final class SnippetsStore {
    enum State: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var snippets: [StoredSnippet] = []
    private(set) var folders: [SnippetFolder] = []
    private(set) var state: State = .idle
    private(set) var issues: [SnippetRepository.Issue] = []
    private(set) var operationError: String?

    private(set) var snippetsDirectory: URL
    var onSnapshot: ((SnippetRepository.Snapshot) -> Void)?
    var onSnippetIDsMoved: (([(oldID: StoredSnippet.ID, newID: StoredSnippet.ID)]) -> Void)?

    private var repository: SnippetRepository
    @ObservationIgnored private var directoryWatchers: [String: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var watcherRetryTask: Task<Void, Never>?
    private var generation = 0
    private var watcherGeneration = 0
    private var isStarted = false

    init(repository: SnippetRepository = SnippetRepository()) {
        self.repository = repository
        snippetsDirectory = repository.snippetsDirectory
    }

    isolated deinit {
        reloadTask?.cancel()
        watcherRetryTask?.cancel()
        for source in directoryWatchers.values { source.cancel() }
        for source in fileWatchers.values { source.cancel() }
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        await reload(showLoadingState: true)
    }

    func stop() {
        isStarted = false
        generation &+= 1
        reloadTask?.cancel()
        reloadTask = nil
        watcherRetryTask?.cancel()
        watcherRetryTask = nil
        stopWatchers()
    }

    func relocate(to repository: SnippetRepository) async {
        guard repository.snippetsDirectory != snippetsDirectory else { return }
        let wasStarted = isStarted
        stop()
        self.repository = repository
        snippetsDirectory = repository.snippetsDirectory
        // Emptied first, so a folder that fails to load leaves no old snippet expanding.
        if !snippets.isEmpty || !folders.isEmpty || !issues.isEmpty {
            snippets = []
            folders = []
            issues = []
            onSnapshot?(SnippetRepository.Snapshot(records: [], folders: [], issues: []))
        }
        guard wasStarted else { return }
        await start()
    }

    func retry() {
        guard isStarted else { return }
        scheduleReload(after: .zero, showLoadingState: true)
    }

    @discardableResult
    func create(_ snippet: Snippet) async throws -> StoredSnippet {
        let record = try await performMutation { try $0.create(snippet) }
        guard isStarted else { return record }
        var records = snippets.filter { $0.id != record.id }
        records.append(record)
        let updatedFolders = mergingAncestorFolders(for: record.snippet.folder, into: folders)
        publishLocal(records: records, folders: updatedFolders)
        scheduleReload(after: .zero)
        return record
    }

    @discardableResult
    func importSnippets(_ imported: [Snippet]) async throws -> [StoredSnippet] {
        guard !imported.isEmpty else { return [] }
        let created = try await performMutation { try $0.create(imported) }
        guard isStarted else { return created }
        let createdIDs = Set(created.map(\.id))
        var updatedFolders = folders
        for record in created {
            updatedFolders = mergingAncestorFolders(for: record.snippet.folder, into: updatedFolders)
        }
        publishLocal(records: snippets.filter { !createdIDs.contains($0.id) } + created, folders: updatedFolders)
        scheduleReload(after: .zero)
        return created
    }

    @discardableResult
    func save(_ record: StoredSnippet) async throws -> StoredSnippet {
        let oldID = record.id
        let saved = try await performMutation {
            try $0.save(
                record.snippet,
                fileURL: record.fileURL,
                expectedRevision: record.sourceRevision)
        }
        if saved.id != oldID {
            onSnippetIDsMoved?([(oldID: oldID, newID: saved.id)])
        }
        guard isStarted else { return saved }
        var records = snippets.filter { $0.id != oldID && $0.id != saved.id }
        records.append(saved)
        let updatedFolders = mergingAncestorFolders(for: saved.snippet.folder, into: folders)
        publishLocal(records: records, folders: updatedFolders)
        scheduleReload(after: .zero)
        return saved
    }

    func delete(id: StoredSnippet.ID) async throws {
        guard let record = record(id: id) else {
            throw SnippetRepository.RepositoryError.fileNotFound(URL(fileURLWithPath: id))
        }
        try await performMutation {
            try $0.delete(
                fileURL: record.fileURL,
                expectedRevision: record.sourceRevision)
        }
        guard isStarted else { return }
        publishLocal(records: snippets.filter { $0.id != id }, folders: folders)
        scheduleReload(after: .zero)
    }

    @discardableResult
    func createFolder(
        path: String,
        metadata: SnippetFolderMetadata = SnippetFolderMetadata()
    ) async throws -> SnippetFolder {
        let created = try await performMutation { try $0.createFolder(path: path, metadata: metadata) }
        guard isStarted else { return created }
        var updatedFolders = mergingAncestorFolders(for: created.path, into: folders)
        updatedFolders = updatedFolders.filter { $0.path != created.path } + [created]
        publishLocal(records: snippets, folders: updatedFolders)
        scheduleReload(after: .zero)
        return created
    }

    @discardableResult
    func updateFolderMetadata(
        _ metadata: SnippetFolderMetadata,
        at path: String
    ) async throws -> SnippetFolder {
        let updated = try await performMutation { try $0.updateFolderMetadata(metadata, at: path) }
        guard isStarted else { return updated }
        let updatedFolders = folders.filter { $0.path != updated.path } + [updated]
        publishLocal(records: snippets, folders: updatedFolders)
        scheduleReload(after: .zero)
        return updated
    }

    @discardableResult
    func renameFolder(from oldPath: String, to newPath: String) async throws -> SnippetFolder {
        let result = try await performMutation { try $0.renameFolder(from: oldPath, to: newPath) }
        if !result.movedIDs.isEmpty {
            onSnippetIDsMoved?(result.movedIDs)
        }
        guard isStarted else { return result.folder }
        let snapshot = try? await performMutation { try $0.load() }
        if let snapshot {
            apply(snapshot)
        } else {
            scheduleReload(after: .zero)
        }
        return result.folder
    }

    func deleteFolder(at path: String) async throws {
        _ = try await performMutation { try $0.deleteFolder(at: path) }
        guard isStarted else { return }
        let remainingSnippets = snippets.filter {
            !SnippetFolderPolicy.contains($0.snippet.folder, in: path)
        }
        let remainingFolders = folders.filter {
            $0.path != path && !$0.path.hasPrefix(path + "/")
        }
        publishLocal(records: remainingSnippets, folders: remainingFolders)
        scheduleReload(after: .zero)
    }

    func record(id: StoredSnippet.ID) -> StoredSnippet? {
        snippets.first(where: { $0.id == id })
    }

    var foldersByPath: [String: SnippetFolder] {
        SnippetFolderPolicy.foldersByPath(from: folders)
    }

    func folder(at path: String) -> SnippetFolder? {
        folders.first(where: { $0.path == path })
    }

    func folderURL(for path: String) -> URL {
        var url = snippetsDirectory
        for component in SnippetFolderPath.components(of: path) {
            url.appendPathComponent(component, isDirectory: true)
        }
        return url
    }

    func isFolderEffectivelyEnabled(_ path: String) -> Bool {
        SnippetFolderPolicy.isFolderEffectivelyEnabled(path, foldersByPath: foldersByPath)
    }

    func isSnippetEffectivelyEnabled(_ record: StoredSnippet) -> Bool {
        SnippetFolderPolicy.isSnippetEffectivelyEnabled(record.snippet, foldersByPath: foldersByPath)
    }

    func isSnippetEffectivelyEnabled(id: StoredSnippet.ID) -> Bool {
        guard let record = record(id: id) else { return false }
        return isSnippetEffectivelyEnabled(record)
    }

    func effectivePrefix(for folderPath: String?) -> String {
        SnippetFolderPolicy.effectivePrefix(for: folderPath, foldersByPath: foldersByPath)
    }

    func effectiveKeyword(for record: StoredSnippet) -> String? {
        SnippetFolderPolicy.effectiveKeyword(for: record.snippet, foldersByPath: foldersByPath)
    }

    func childFolders(in parentPath: String?, includeDisabled: Bool = false) -> [SnippetFolder] {
        let map = foldersByPath
        return folders.filter { folder in
            guard folder.parentPath == parentPath else { return false }
            if !includeDisabled {
                return SnippetFolderPolicy.isFolderEffectivelyEnabled(folder.path, foldersByPath: map)
            }
            return true
        }
    }

    func directSnippets(in folderPath: String?, includeDisabled: Bool = false) -> [StoredSnippet] {
        let map = foldersByPath
        return snippets.filter { record in
            guard record.snippet.folder == folderPath else { return false }
            if !includeDisabled {
                return SnippetFolderPolicy.isSnippetEffectivelyEnabled(record.snippet, foldersByPath: map)
            }
            return true
        }
    }

    func snippetCount(in folderPath: String, includeDisabled: Bool = false) -> Int {
        let map = foldersByPath
        return snippets.count { record in
            guard SnippetFolderPolicy.contains(record.snippet.folder, in: folderPath) else { return false }
            if !includeDisabled {
                return SnippetFolderPolicy.isSnippetEffectivelyEnabled(record.snippet, foldersByPath: map)
            }
            return true
        }
    }

    func subfolderCount(in folderPath: String, includeDisabled: Bool = false) -> Int {
        let map = foldersByPath
        return folders.count { folder in
            guard folder.path.hasPrefix(folderPath + "/") else { return false }
            if !includeDisabled {
                return SnippetFolderPolicy.isFolderEffectivelyEnabled(folder.path, foldersByPath: map)
            }
            return true
        }
    }

    /// A disabled snippet is off everywhere, so the browser lists exactly what the launcher does.
    func browserRows(matching query: String, in folderPath: String? = nil) -> [StoredSnippet] {
        let map = foldersByPath
        let enabled = snippets.filter { record in
            guard SnippetFolderPolicy.isSnippetEffectivelyEnabled(record.snippet, foldersByPath: map) else {
                return false
            }
            if let folderPath {
                return SnippetFolderPolicy.contains(record.snippet.folder, in: folderPath)
            }
            return true
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return enabled.filter(\.snippet.isPinned) + enabled.filter { !$0.snippet.isPinned }
        }
        return SnippetSearch.rank(enabled, foldersByPath: map, for: trimmed)
    }

    private enum RepositoryResult<Value: Sendable>: Sendable {
        case success(Value)
        case failure(SnippetRepository.RepositoryError)
    }

    private func performMutation<Value: Sendable>(
        _ operation: @escaping @Sendable (SnippetRepository) throws -> Value
    ) async throws -> Value {
        reloadTask?.cancel()
        reloadTask = nil
        generation &+= 1
        let repository = repository

        let result = await Task.detached(priority: .utility) {
            do {
                return RepositoryResult.success(try operation(repository))
            } catch let error as SnippetRepository.RepositoryError {
                return RepositoryResult.failure(error)
            } catch {
                return RepositoryResult.failure(
                    .io(
                        fileURL: repository.snippetsDirectory,
                        message: error.localizedDescription))
            }
        }.value

        switch result {
        case .success(let value):
            operationError = nil
            return value
        case .failure(let error):
            operationError = error.localizedDescription
            throw error
        }
    }

    private func reload(showLoadingState: Bool) async {
        guard isStarted else { return }
        generation &+= 1
        let loadGeneration = generation
        if showLoadingState { state = .loading }
        let repository = repository

        let result = await Task.detached(priority: .utility) {
            do {
                return RepositoryResult.success(try repository.load())
            } catch let error as SnippetRepository.RepositoryError {
                return RepositoryResult.failure(error)
            } catch {
                return RepositoryResult.failure(
                    .io(
                        fileURL: repository.snippetsDirectory,
                        message: error.localizedDescription))
            }
        }.value

        guard isStarted, loadGeneration == generation else { return }
        switch result {
        case .success(let snapshot):
            apply(snapshot)
        case .failure(let error):
            state = .failed(error.localizedDescription)
            scheduleWatcherRetry()
        }
    }

    private func publishLocal(records: [StoredSnippet], folders: [SnippetFolder]) {
        let sortedFolders = folders.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
        apply(
            SnippetRepository.Snapshot(
                records: records.sorted(by: recordOrder),
                folders: sortedFolders,
                issues: issues))
    }

    private func mergingAncestorFolders(
        for folderPath: String?,
        into existing: [SnippetFolder]
    ) -> [SnippetFolder] {
        guard let folderPath, let normalized = SnippetFolderPath.validated(folderPath) else {
            return existing
        }
        var map = SnippetFolderPolicy.foldersByPath(from: existing)
        for ancestor in SnippetFolderPath.ancestorPaths(of: normalized) where map[ancestor] == nil {
            map[ancestor] = SnippetFolder(path: ancestor)
        }
        return Array(map.values)
    }

    private func apply(_ snapshot: SnippetRepository.Snapshot) {
        guard isStarted else { return }
        let isUnchanged =
            state == .ready
            && snippets == snapshot.records
            && folders == snapshot.folders
            && issues == snapshot.issues
        if !isUnchanged {
            snippets = snapshot.records
            folders = snapshot.folders
            issues = snapshot.issues
            state = .ready
            onSnapshot?(snapshot)
        }
        if syncWatchers(with: snapshot) {
            scheduleReload(after: .milliseconds(150))
        }
    }

    private func scheduleReload(after delay: Duration, showLoadingState: Bool = false) {
        guard isStarted else { return }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            if delay != .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
            guard let self, self.isStarted, !Task.isCancelled else { return }
            await self.reload(showLoadingState: showLoadingState)
        }
    }

    private func syncWatchers(with snapshot: SnippetRepository.Snapshot) -> Bool {
        guard isStarted else { return false }
        watcherRetryTask?.cancel()
        watcherRetryTask = nil

        var changed = false
        let desiredDirectories = Set(
            [snippetsDirectory.standardizedFileURL.path]
                + snapshot.folders.map { folderURL(for: $0.path).standardizedFileURL.path })
        for path in Array(directoryWatchers.keys) where !desiredDirectories.contains(path) {
            directoryWatchers.removeValue(forKey: path)?.cancel()
            changed = true
        }
        for path in desiredDirectories where directoryWatchers[path] == nil {
            changed = armDirectoryWatcher(path: path) || changed
        }

        let desiredPaths = Set(
            snapshot.records.map { $0.fileURL.standardizedFileURL.path }
                + snapshot.issues.map { $0.fileURL.standardizedFileURL.path })
        for path in Array(fileWatchers.keys) where !desiredPaths.contains(path) {
            fileWatchers.removeValue(forKey: path)?.cancel()
            changed = true
        }
        for path in desiredPaths where fileWatchers[path] == nil {
            changed = armFileWatcher(path: path) || changed
        }

        // Retry while anything is unwatched; a failed file watcher blinds us like a missing one.
        if desiredDirectories.contains(where: { directoryWatchers[$0] == nil })
            || desiredPaths.contains(where: { fileWatchers[$0] == nil })
        {
            scheduleWatcherRetry()
        }
        return changed
    }

    @discardableResult
    private func armDirectoryWatcher(path: String) -> Bool {
        let descriptor = Darwin.open(path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        if path == snippetsDirectory.standardizedFileURL.path {
            watcherGeneration &+= 1
        }
        let installedGeneration = watcherGeneration
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleDirectoryEvent(path: path, generation: installedGeneration)
            }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        directoryWatchers[path] = source
        source.resume()
        return true
    }

    @discardableResult
    private func armFileWatcher(path: String) -> Bool {
        let descriptor = Darwin.open(path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let installedGeneration = watcherGeneration
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleFileEvent(path: path, generation: installedGeneration)
            }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        fileWatchers[path] = source
        source.resume()
        return true
    }

    private func handleDirectoryEvent(path: String, generation installedGeneration: Int) {
        guard isStarted, installedGeneration == watcherGeneration,
            let events = directoryWatchers[path]?.data
        else { return }

        if !events.isDisjoint(with: [.delete, .rename, .revoke]) {
            if path == snippetsDirectory.standardizedFileURL.path {
                stopWatchers()
            } else {
                directoryWatchers.removeValue(forKey: path)?.cancel()
            }
        }
        noteFilesystemChange()
    }

    private func handleFileEvent(path: String, generation installedGeneration: Int) {
        guard isStarted, installedGeneration == watcherGeneration,
            let source = fileWatchers[path]
        else { return }

        if !source.data.isDisjoint(with: [.delete, .rename, .revoke]) {
            fileWatchers.removeValue(forKey: path)?.cancel()
        }
        noteFilesystemChange()
    }

    private func noteFilesystemChange() {
        generation &+= 1
        scheduleReload(after: .milliseconds(150))
    }

    private func stopWatchers() {
        watcherGeneration &+= 1
        for source in directoryWatchers.values { source.cancel() }
        directoryWatchers.removeAll()
        for source in fileWatchers.values { source.cancel() }
        fileWatchers.removeAll()
    }

    private func scheduleWatcherRetry() {
        guard isStarted, watcherRetryTask == nil else { return }
        watcherRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard let self, self.isStarted, !Task.isCancelled else { return }
            self.watcherRetryTask = nil
            await self.reload(showLoadingState: false)
        }
    }

    private func recordOrder(_ lhs: StoredSnippet, _ rhs: StoredSnippet) -> Bool {
        let comparison = lhs.snippet.name.localizedCaseInsensitiveCompare(rhs.snippet.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id < rhs.id
    }
}
