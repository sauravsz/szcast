import AppKit
import Foundation
import OSLog

@MainActor
final class KeePassXCService: Observable {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "KeePassXC")
    private static let masterPasswordKey = "masterPassword"

    private let keychain: KeychainSecretStore

    var onHidePalette: (() -> Void)?
    var onShowMessage: ((String) -> Void)?

    var resumedEntry: KeePassXCEntry?
    var selectedEntry: KeePassXCEntry?
    var entries: [KeePassXCEntry] = []
    var filteredEntries: [KeePassXCEntry] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private var entryDetailCache: [String: KeePassXCEntry] = [:]

    init(keychain: KeychainSecretStore = .keepassXCSecrets) {
        self.keychain = keychain
    }

    var databasePath: String {
        get { UserDefaults.standard.string(forKey: "keepassxc.databasePath") ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: "keepassxc.databasePath")
            entryDetailCache.removeAll()
            entries.removeAll()
            filteredEntries.removeAll()
        }
    }

    var keyfilePath: String {
        get { UserDefaults.standard.string(forKey: "keepassxc.keyfilePath") ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: "keepassxc.keyfilePath")
            entryDetailCache.removeAll()
        }
    }

    var customCliPath: String {
        get { UserDefaults.standard.string(forKey: "keepassxc.cliPath") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "keepassxc.cliPath") }
    }

    var masterPassword: String? {
        get { try? keychain.secret(for: Self.masterPasswordKey) }
        set {
            if let newValue = newValue, !newValue.isEmpty {
                try? keychain.setSecret(newValue, for: Self.masterPasswordKey)
            } else {
                try? keychain.removeSecret(for: Self.masterPasswordKey)
            }
            entryDetailCache.removeAll()
        }
    }

    var isConfigured: Bool {
        !databasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasKeyfile: Bool {
        let kf = keyfilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return !kf.isEmpty && FileManager.default.fileExists(atPath: kf)
    }

    var isUnlocked: Bool {
        (masterPassword != nil && !masterPassword!.isEmpty) || hasKeyfile
    }

    func resolveCliPath() -> String? {
        if !customCliPath.isEmpty && FileManager.default.isExecutableFile(atPath: customCliPath) {
            return customCliPath
        }
        let candidates = [
            "/opt/homebrew/bin/keepassxc-cli",
            "/usr/local/bin/keepassxc-cli",
            "/usr/bin/keepassxc-cli"
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    enum KeePassXCError: LocalizedError {
        case cliNotFound
        case databaseNotFound(String)
        case executionFailed(Int32, String)
        case missingPassword
        case invalidEntry

        var errorDescription: String? {
            switch self {
            case .cliNotFound:
                return String(localized: "keepassxc-cli binary not found. Please install KeePassXC via Homebrew (brew install keepassxc).")
            case .databaseNotFound(let path):
                return String(localized: "KeePassXC database not found at path: \(path)")
            case .executionFailed(let code, let msg):
                return String(localized: "KeePassXC CLI error (\(code)): \(msg)")
            case .missingPassword:
                return String(localized: "Master password is required to unlock the database.")
            case .invalidEntry:
                return String(localized: "Specified KeePassXC entry could not be found.")
            }
        }
    }

    // MARK: - Process Execution

    private func executeCli(arguments: [String], input: String?) async throws -> String {
        guard let cli = resolveCliPath() else {
            throw KeePassXCError.cliNotFound
        }

        let db = databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FileManager.default.fileExists(atPath: db) else {
            throw KeePassXCError.databaseNotFound(db)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cli)
                process.arguments = arguments

                let stdinPipe = Pipe()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardInput = stdinPipe
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    if let input = input, let data = (input + "\n").data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                    }
                    try? stdinPipe.fileHandleForWriting.close()

                    final class PipeBuffer: @unchecked Sendable {
                        var data = Data()
                    }
                    let outBox = PipeBuffer()
                    let errBox = PipeBuffer()
                    let pipeGroup = DispatchGroup()

                    pipeGroup.enter()
                    DispatchQueue.global().async {
                        outBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        pipeGroup.leave()
                    }

                    pipeGroup.enter()
                    DispatchQueue.global().async {
                        errBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        pipeGroup.leave()
                    }

                    pipeGroup.wait()
                    process.waitUntilExit()

                    let outString = String(data: outBox.data, encoding: .utf8) ?? ""
                    let errString = String(data: errBox.data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: outString)
                    } else {
                        let combined = (errString.isEmpty ? outString : errString).trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: KeePassXCError.executionFailed(process.terminationStatus, combined))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Entry Listing & Filtering

    func loadEntries() async {
        guard isConfigured else {
            errorMessage = String(localized: "Please configure your KeePassXC database path in Settings.")
            return
        }
        let password = masterPassword ?? ""
        guard !password.isEmpty || hasKeyfile else {
            errorMessage = String(localized: "Database is locked. Please enter your master password or select a keyfile.")
            return
        }

        isLoading = true
        errorMessage = nil

        var args = ["ls", "-q", "-R", "-f"]
        let kf = keyfilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kf.isEmpty && FileManager.default.fileExists(atPath: kf) {
            args.append(contentsOf: ["-k", kf])
        }
        if password.isEmpty && hasKeyfile {
            args.append("--no-password")
        }
        args.append(databasePath)

        do {
            let output = try await executeCli(arguments: args, input: password.isEmpty ? nil : password)
            let lines = output.components(separatedBy: .newlines)
            var loaded: [KeePassXCEntry] = []

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                // Filter out empty lines and directory/group names that end in "/"
                guard !trimmed.isEmpty, !trimmed.hasSuffix("/") else { continue }
                let parts = trimmed.components(separatedBy: "/")
                let title = parts.last ?? trimmed
                let group = parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
                loaded.append(KeePassXCEntry(path: trimmed, title: title, group: group))
            }

            self.entries = loaded
            self.filteredEntries = loaded
            self.isLoading = false
            Self.logger.info("Loaded \(loaded.count) KeePassXC entries")
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            Self.logger.error("Failed to load KeePassXC entries: \(error.localizedDescription)")
        }
    }

    func searchCli(term: String) async throws -> [KeePassXCEntry] {
        guard isConfigured, isUnlocked else { return [] }
        var args = ["search", "-q"]
        let kf = keyfilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kf.isEmpty && FileManager.default.fileExists(atPath: kf) {
            args.append(contentsOf: ["-k", kf])
        }
        let password = masterPassword ?? ""
        if password.isEmpty && hasKeyfile {
            args.append("--no-password")
        }
        args.append(contentsOf: [databasePath, term])
        let output = try await executeCli(arguments: args, input: password.isEmpty ? nil : password)
        let lines = output.components(separatedBy: .newlines)
        var result: [KeePassXCEntry] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasSuffix("/") else { continue }
            if let existing = entries.first(where: { $0.path == trimmed }) {
                result.append(existing)
            } else {
                let parts = trimmed.components(separatedBy: "/")
                let title = parts.last ?? trimmed
                let group = parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
                result.append(KeePassXCEntry(path: trimmed, title: title, group: group))
            }
        }
        return result
    }

    func filterEntries(query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.isEmpty {
            filteredEntries = entries
        } else {
            let matched = entries.filter { entry in
                entry.title.localizedCaseInsensitiveContains(clean) ||
                entry.path.localizedCaseInsensitiveContains(clean) ||
                (entry.username.localizedCaseInsensitiveContains(clean)) ||
                (entry.group?.localizedCaseInsensitiveContains(clean) ?? false) ||
                (entryDetailCache[entry.path]?.username.localizedCaseInsensitiveContains(clean) ?? false)
            }
            filteredEntries = matched
            if matched.isEmpty && isUnlocked {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let results = try? await self.searchCli(term: query), !results.isEmpty {
                        var combined = self.filteredEntries
                        for r in results where !combined.contains(where: { $0.path == r.path }) {
                            combined.append(r)
                        }
                        self.filteredEntries = combined
                    }
                }
            }
        }
    }

    // MARK: - Entry Details & Attributes

    func fetchEntryDetails(entryPath: String) async throws -> KeePassXCEntry {
        if let cached = entryDetailCache[entryPath], !cached.password.isEmpty {
            return cached
        }

        let password = masterPassword ?? ""
        guard !password.isEmpty || hasKeyfile else {
            throw KeePassXCError.missingPassword
        }

        var args = ["show", "-q", "-s", "--all"]
        let kf = keyfilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kf.isEmpty && FileManager.default.fileExists(atPath: kf) {
            args.append(contentsOf: ["-k", kf])
        }
        if password.isEmpty && hasKeyfile {
            args.append("--no-password")
        }
        args.append(contentsOf: [databasePath, entryPath])

        let output = try await executeCli(arguments: args, input: password.isEmpty ? nil : password)
        var entry = KeePassXCEntry(path: entryPath)

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "title": entry.title = value
            case "username": entry.username = value
            case "password": entry.password = value
            case "url": entry.url = value
            case "notes": entry.notes = value
            case "uuid": entry.uuid = value
            default: break
            }
        }

        entryDetailCache[entryPath] = entry
        if let idx = entries.firstIndex(where: { $0.path == entryPath }) {
            entries[idx].username = entry.username
            entries[idx].title = entry.title
            entries[idx].url = entry.url
        }
        return entry
    }

    func fetchTOTP(entryPath: String) async throws -> String {
        let password = masterPassword ?? ""
        guard !password.isEmpty || hasKeyfile else {
            throw KeePassXCError.missingPassword
        }

        var args = ["show", "-q", "-s", "-t"]
        let kf = keyfilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kf.isEmpty && FileManager.default.fileExists(atPath: kf) {
            args.append(contentsOf: ["-k", kf])
        }
        if password.isEmpty && hasKeyfile {
            args.append("--no-password")
        }
        args.append(contentsOf: [databasePath, entryPath])

        let output = try await executeCli(arguments: args, input: password.isEmpty ? nil : password)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("has no TOTP set up") || trimmed.isEmpty {
            throw KeePassXCError.executionFailed(1, "No TOTP configured for \(entryPath)")
        }
        return trimmed
    }

    // MARK: - Shortcut Actions (cmd+C, cmd+T, cmd+B, cmd+U)

    func handleShortcutCopyPassword(entry: KeePassXCEntry? = nil) {
        guard let target = entry ?? resumedEntry ?? selectedEntry else { return }
        Task { @MainActor in
            do {
                let password: String
                let fullEntry: KeePassXCEntry
                if !target.password.isEmpty {
                    password = target.password
                    fullEntry = target
                } else {
                    let fetched = try await self.fetchEntryDetails(entryPath: target.path)
                    password = fetched.password
                    fullEntry = fetched
                }
                guard !password.isEmpty else {
                    self.onShowMessage?("No password stored for \(target.title)")
                    return
                }
                self.copyConcealed(password)
                self.resumedEntry = fullEntry
                self.onShowMessage?("Copied password for \(target.title)")
                self.onHidePalette?()
            } catch {
                self.onShowMessage?("Failed to copy password: \(error.localizedDescription)")
            }
        }
    }

    func handleShortcutCopyTOTP(entry: KeePassXCEntry? = nil) {
        guard let target = entry ?? resumedEntry ?? selectedEntry else { return }
        Task { @MainActor in
            do {
                let totp = try await self.fetchTOTP(entryPath: target.path)
                self.copyConcealed(totp)
                self.resumedEntry = target
                self.onShowMessage?("Copied TOTP code: \(totp)")
                self.onHidePalette?()
            } catch {
                self.onShowMessage?("No TOTP found for \(target.title)")
            }
        }
    }

    func handleShortcutCopyUsername(entry: KeePassXCEntry? = nil) {
        guard let target = entry ?? resumedEntry ?? selectedEntry else { return }
        Task { @MainActor in
            do {
                let username: String
                let fullEntry: KeePassXCEntry
                if !target.username.isEmpty {
                    username = target.username
                    fullEntry = target
                } else {
                    let fetched = try await self.fetchEntryDetails(entryPath: target.path)
                    username = fetched.username
                    fullEntry = fetched
                }
                guard !username.isEmpty else {
                    self.onShowMessage?("No username stored for \(target.title)")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(username, forType: .string)
                self.resumedEntry = fullEntry
                self.onShowMessage?("Copied username: \(username)")
                self.onHidePalette?()
            } catch {
                self.onShowMessage?("Failed to copy username: \(error.localizedDescription)")
            }
        }
    }

    func handleShortcutOpenURL(entry: KeePassXCEntry? = nil) {
        guard let target = entry ?? resumedEntry ?? selectedEntry else { return }
        Task { @MainActor in
            do {
                let rawURL: String
                let fullEntry: KeePassXCEntry
                if !target.url.isEmpty {
                    rawURL = target.url
                    fullEntry = target
                } else {
                    let fetched = try await self.fetchEntryDetails(entryPath: target.path)
                    rawURL = fetched.url
                    fullEntry = fetched
                }
                var cleanURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanURL.isEmpty else {
                    self.onShowMessage?("No URL stored for \(target.title)")
                    return
                }
                if !cleanURL.contains("://") {
                    cleanURL = "https://" + cleanURL
                }
                if let url = URL(string: cleanURL) {
                    NSWorkspace.shared.open(url)
                    self.resumedEntry = fullEntry
                    self.onShowMessage?("Opened \(target.title) URL")
                    self.onHidePalette?()
                } else {
                    self.onShowMessage?("Invalid URL: \(cleanURL)")
                }
            } catch {
                self.onShowMessage?("Failed to open URL: \(error.localizedDescription)")
            }
        }
    }

    func clearResumedEntry() {
        resumedEntry = nil
    }

    private func copyConcealed(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let autoGenerated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
        let peterMaurer = NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType")
        let appleSensitive = NSPasteboard.PasteboardType("com.apple.is-sensitive")
        let internalType = NSPasteboard.PasteboardType("com.sauravsz.szcast.internal")
        pb.declareTypes([.string, concealed, transient, autoGenerated, peterMaurer, appleSensitive, internalType], owner: nil)
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: concealed)
        pb.setData(Data(), forType: transient)
        pb.setData(Data(), forType: autoGenerated)
        pb.setData(Data(), forType: peterMaurer)
        pb.setData(Data(), forType: appleSensitive)
        pb.setData(Data(), forType: internalType)
    }
}
