import AppKit
import Foundation
import OSLog

@MainActor
final class FinderFileActionsService: Observable {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "FinderFileActions")

    private let storeDirectory: URL
    private let pinnedFileURL: URL
    private let recentFileURL: URL

    private(set) var pinnedFolders: [URL] = []
    private(set) var recentFolders: [URL] = []

    init(storeDirectory: URL? = nil) {
        let dir = storeDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("szcast", isDirectory: true)
            .appendingPathComponent("FinderFileActions", isDirectory: true)

        self.storeDirectory = dir
        self.pinnedFileURL = dir.appendingPathComponent("pinned_folders.json")
        self.recentFileURL = dir.appendingPathComponent("recent_folders.json")

        loadPinned()
        loadRecent()
    }

    // MARK: - Pinned & Recent Folders

    private func defaultPinnedFolders() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("AIOS")
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func loadPinned() {
        guard FileManager.default.fileExists(atPath: pinnedFileURL.path) else {
            pinnedFolders = defaultPinnedFolders()
            return
        }

        do {
            let data = try Data(contentsOf: pinnedFileURL)
            let paths = try JSONDecoder().decode([String].self, from: data)
            pinnedFolders = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            if pinnedFolders.isEmpty {
                pinnedFolders = defaultPinnedFolders()
            }
        } catch {
            pinnedFolders = defaultPinnedFolders()
        }
    }

    func savePinned() {
        do {
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            let paths = pinnedFolders.map(\.path)
            let data = try JSONEncoder().encode(paths)
            try data.write(to: pinnedFileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save pinned folders: \(error.localizedDescription)")
        }
    }

    func togglePin(folder: URL) -> Bool {
        let standard = folder.standardizedFileURL
        if let idx = pinnedFolders.firstIndex(where: { $0.standardizedFileURL.path == standard.path }) {
            pinnedFolders.remove(at: idx)
            savePinned()
            return false
        } else {
            pinnedFolders.append(standard)
            savePinned()
            return true
        }
    }

    func loadRecent() {
        guard FileManager.default.fileExists(atPath: recentFileURL.path) else {
            recentFolders = []
            return
        }

        do {
            let data = try Data(contentsOf: recentFileURL)
            let paths = try JSONDecoder().decode([String].self, from: data)
            recentFolders = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        } catch {
            recentFolders = []
        }
    }

    func saveRecent() {
        do {
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            let paths = recentFolders.map(\.path)
            let data = try JSONEncoder().encode(paths)
            try data.write(to: recentFileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save recent folders: \(error.localizedDescription)")
        }
    }

    func addRecentFolder(_ folder: URL) {
        let standard = folder.standardizedFileURL
        recentFolders.removeAll { $0.standardizedFileURL.path == standard.path }
        recentFolders.insert(standard, at: 0)
        if recentFolders.count > 15 {
            recentFolders = Array(recentFolders.prefix(15))
        }
        saveRecent()
    }

    // MARK: - Finder Interop

    /// Retrieves current selection from the frontmost Finder window.
    func getSelectedItems() -> [URL] {
        let script = """
        tell application "Finder"
            set theSelection to selection as alias list
            set posixList to {}
            repeat with anItem in theSelection
                set end of posixList to POSIX path of anItem
            end repeat
            set AppleScript's text item delimiters to linefeed
            return posixList as text
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return [] }
        let output = appleScript.executeAndReturnError(&error)
        if error != nil { return [] }

        guard let text = output.stringValue, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let lines = text.components(separatedBy: .newlines)
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Spotlight Search

    func searchSpotlightFolders(query: String, limit: Int = 25) -> [URL] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
        guard !clean.isEmpty else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [
            "-onlyin", home,
            "kMDItemContentType == 'public.folder' && (kMDItemDisplayName == '*\(clean)*'cd || kMDItemPath == '*\(clean)*'cd)"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            let ignored = [
                "/.", "/node_modules/", "/DerivedData/", "/Library/Caches/",
                "/Library/Containers/", "/Library/Group Containers/", "/.Trash/",
                "/build/", "/.git/"
            ]

            var results: [URL] = []
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) else { continue }
                if ignored.contains(where: { trimmed.contains($0) }) { continue }

                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir), isDir.boolValue {
                    results.append(URL(fileURLWithPath: trimmed))
                    if results.count >= limit { break }
                }
            }
            return results
        } catch {
            return []
        }
    }

    // MARK: - Duplicate Resolution

    static func getUniquePath(in destinationFolder: URL, for originalName: String, isDirectory: Bool) -> URL {
        let target = destinationFolder.appendingPathComponent(originalName)
        if !FileManager.default.fileExists(atPath: target.path) {
            return target
        }

        let base: String
        let ext: String
        if isDirectory {
            base = originalName
            ext = ""
        } else {
            let url = URL(fileURLWithPath: originalName)
            ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            base = url.deletingPathExtension().lastPathComponent
        }

        var counter = 2
        while true {
            let candidateName = "\(base) \(counter)\(ext)"
            let candidate = destinationFolder.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    // MARK: - Actions

    func moveItems(sources: [URL], to destFolder: URL) throws -> (count: Int, message: String) {
        guard FileManager.default.fileExists(atPath: destFolder.path) else {
            throw NSError(domain: "FinderFileActions", code: 404, userInfo: [NSLocalizedDescriptionKey: "Destination folder does not exist."])
        }

        var movedCount = 0
        for src in sources {
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir)

            let destTarget = Self.getUniquePath(in: destFolder, for: src.lastPathComponent, isDirectory: isDir.boolValue)
            try FileManager.default.moveItem(at: src, to: destTarget)
            movedCount += 1
        }

        addRecentFolder(destFolder)
        let name = destFolder.lastPathComponent
        let label = movedCount == 1 ? "1 item" : "\(movedCount) items"
        return (movedCount, String(localized: "Moved \(label) to \"\(name)\""))
    }

    func copyItems(sources: [URL], to destFolder: URL) throws -> (count: Int, message: String) {
        guard FileManager.default.fileExists(atPath: destFolder.path) else {
            throw NSError(domain: "FinderFileActions", code: 404, userInfo: [NSLocalizedDescriptionKey: "Destination folder does not exist."])
        }

        var copiedCount = 0
        for src in sources {
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir)

            let destTarget = Self.getUniquePath(in: destFolder, for: src.lastPathComponent, isDirectory: isDir.boolValue)
            try FileManager.default.copyItem(at: src, to: destTarget)
            copiedCount += 1
        }

        addRecentFolder(destFolder)
        let name = destFolder.lastPathComponent
        let label = copiedCount == 1 ? "1 item" : "\(copiedCount) items"
        return (copiedCount, String(localized: "Copied \(label) to \"\(name)\""))
    }
}
