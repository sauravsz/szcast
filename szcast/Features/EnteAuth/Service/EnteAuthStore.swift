import Foundation
import OSLog

@MainActor
final class EnteAuthStore: Observable {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "EnteAuth")

    private let storeDirectory: URL
    private let storeFileURL: URL

    private(set) var accounts: [EnteAuthAccount] = []

    init(storeDirectory: URL? = nil) {
        let dir = storeDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("szcast", isDirectory: true)
            .appendingPathComponent("EnteAuth", isDirectory: true)

        self.storeDirectory = dir
        self.storeFileURL = dir.appendingPathComponent("accounts.json")

        loadAccounts()
    }

    // MARK: - Persistence

    func loadAccounts() {
        guard FileManager.default.fileExists(atPath: storeFileURL.path) else {
            accounts = []
            return
        }

        do {
            let data = try Data(contentsOf: storeFileURL)
            let decoded = try JSONDecoder().decode([EnteAuthAccount].self, from: data)
            accounts = decoded
        } catch {
            Self.logger.error("Failed to load Ente Auth accounts: \(error.localizedDescription)")
            accounts = []
        }
    }

    func saveAccounts() {
        do {
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(accounts)
            try data.write(to: storeFileURL, options: .atomic)
            // Restrict permissions to owner-only
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeFileURL.path)
        } catch {
            Self.logger.error("Failed to save Ente Auth accounts: \(error.localizedDescription)")
        }
    }

    // MARK: - Account Management

    func recordUsage(id: UUID) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].useCount += 1
        accounts[idx].lastUsedAt = Date()
        saveAccounts()
    }

    func addAccount(_ account: EnteAuthAccount) {
        if let idx = accounts.firstIndex(where: { $0.secret == account.secret }) {
            accounts[idx] = account
        } else {
            accounts.append(account)
        }
        saveAccounts()
    }

    func deleteAccount(id: UUID) {
        accounts.removeAll { $0.id == id }
        saveAccounts()
    }

    // MARK: - Auto-Discovery & Import

    /// Candidate export file locations where ente_auth.txt typically resides.
    func findExportFile() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Downloads/ente_auth.txt"),
            home.appendingPathComponent("Downloads/ente-auth.txt"),
            home.appendingPathComponent("Documents/ente_auth.txt"),
            home.appendingPathComponent("Documents/ente-auth.txt"),
            home.appendingPathComponent(".ente/ente_auth.txt")
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: candidate.path),
                   let size = attrs[.size] as? UInt64, size > 0 {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Parses an individual otpauth URI (e.g. `otpauth://totp/GitHub:user?secret=JBSWY3DPEHPK3PXP&issuer=GitHub`)
    static func parseOTPAuthURI(_ line: String) -> EnteAuthAccount? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("otpauth://") else { return nil }

        guard let components = URLComponents(string: trimmed) else { return nil }
        guard let host = components.host?.lowercased(), host == "totp" else { return nil }

        // Path contains the label: [Issuer:]Account
        var label = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        label = label.removingPercentEncoding ?? label

        var issuerFromLabel = ""
        var usernameFromLabel = label
        if let colonIndex = label.firstIndex(of: ":") {
            issuerFromLabel = String(label[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let afterColon = label.index(after: colonIndex)
            usernameFromLabel = String(label[afterColon...]).trimmingCharacters(in: .whitespaces)
        }

        var secret = ""
        var issuerFromQuery = ""
        var algorithm: TOTPAlgorithm = .sha1
        var digits = 6
        var period = 30
        var tags: [String] = []

        for item in components.queryItems ?? [] {
            let name = item.name.lowercased()
            let val = item.value ?? ""
            switch name {
            case "secret":
                secret = val
            case "issuer":
                issuerFromQuery = val
            case "algorithm":
                switch val.uppercased() {
                case "SHA256": algorithm = .sha256
                case "SHA512": algorithm = .sha512
                default: algorithm = .sha1
                }
            case "digits":
                if let d = Int(val), d > 0 { digits = d }
            case "period":
                if let p = Int(val), p > 0 { period = p }
            case "tags":
                tags = val.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            default:
                break
            }
        }

        guard !secret.isEmpty else { return nil }

        let resolvedIssuer = !issuerFromQuery.isEmpty ? issuerFromQuery : (!issuerFromLabel.isEmpty ? issuerFromLabel : "Ente")

        return EnteAuthAccount(
            issuer: resolvedIssuer,
            username: usernameFromLabel,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period,
            tags: tags
        )
    }

    /// Imports secrets from the given export file, or auto-discovers one.
    @discardableResult
    func importSecrets(from fileURL: URL? = nil) -> (success: Bool, message: String, count: Int) {
        guard let targetURL = fileURL ?? findExportFile() else {
            return (false, String(localized: "No ente_auth.txt export file found in Downloads or Documents."), 0)
        }

        do {
            let content = try String(contentsOf: targetURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            var importedCount = 0

            for line in lines {
                if let parsed = Self.parseOTPAuthURI(line) {
                    addAccount(parsed)
                    importedCount += 1
                }
            }

            if importedCount > 0 {
                return (true, String(localized: "Successfully imported \(importedCount) 2FA accounts!"), importedCount)
            } else {
                return (false, String(localized: "No valid otpauth:// lines found in \(targetURL.lastPathComponent)."), 0)
            }
        } catch {
            return (false, String(localized: "Failed to read export file: \(error.localizedDescription)"), 0)
        }
    }
}
