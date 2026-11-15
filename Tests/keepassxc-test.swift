import Foundation
import AppKit

@main
@MainActor
struct KeePassXCTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async {
        testEntryModel()
        testServiceState()
        await testShortcutHooks()
        testFilter()

        print("KeePassXCTests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func testEntryModel() {
        let entry = KeePassXCEntry(
            path: "Root/Logins/GitHub",
            title: "GitHub",
            username: "sauravsz",
            password: "supersecretpassword",
            url: "https://github.com",
            notes: "Work credentials",
            uuid: "{12345678-1234-1234-1234-123456789abc}",
            group: "Logins"
        )

        expect(entry.id == "Root/Logins/GitHub", "Entry ID is its path")
        expect(entry.title == "GitHub", "Entry title matches")
        expect(entry.username == "sauravsz", "Entry username matches")
        expect(entry.password == "supersecretpassword", "Entry password matches")
        expect(entry.url == "https://github.com", "Entry URL matches")
        expect(entry.notes == "Work credentials", "Entry notes match")
        expect(entry.uuid == "{12345678-1234-1234-1234-123456789abc}", "Entry UUID matches")
        expect(entry.group == "Logins", "Entry group matches")

        let entryAutoTitle = KeePassXCEntry(path: "Root/Personal/AWS")
        expect(entryAutoTitle.title == "AWS", "Title deduced from leaf path")
    }

    static func testServiceState() {
        let keychain = KeychainSecretStore(scope: "test.kpxc.\(UUID().uuidString)")
        let service = KeePassXCService(keychain: keychain)
        service.databasePath = ""
        service.masterPassword = nil

        expect(!service.isConfigured, "Empty database path is not configured")
        expect(!service.isUnlocked, "No master password is not unlocked")
        expect(service.resumedEntry == nil, "Initial resumedEntry is nil")

        service.masterPassword = "vault_master_password_99"
        expect(service.isUnlocked, "Service is unlocked after setting master password")
        expect(service.masterPassword == "vault_master_password_99", "Retrieved master password matches")

        service.masterPassword = nil
        expect(!service.isUnlocked, "Service locked after clearing master password")

        service.databasePath = "/Users/test/vault.kdbx"
        expect(service.isConfigured, "Service configured after setting database path")
        expect(service.databasePath == "/Users/test/vault.kdbx", "Database path matches")

        let entry = KeePassXCEntry(path: "Root/Logins/GitHub", title: "GitHub", username: "sz")
        service.resumedEntry = entry
        expect(service.resumedEntry?.id == entry.id, "resumedEntry is stored")

        service.clearResumedEntry()
        expect(service.resumedEntry == nil, "resumedEntry cleared via clearResumedEntry()")
    }

    static func testShortcutHooks() async {
        let keychain = KeychainSecretStore(scope: "test.kpxc.\(UUID().uuidString)")
        let service = KeePassXCService(keychain: keychain)
        let entry = KeePassXCEntry(
            path: "Root/Logins/GitHub",
            title: "GitHub",
            username: "sauravsz",
            password: "pword",
            url: "https://szcast.dev"
        )

        var didHidePalette = false
        var shownMessage: String?

        service.onHidePalette = {
            didHidePalette = true
        }
        service.onShowMessage = { msg in
            shownMessage = msg
        }

        service.handleShortcutCopyUsername(entry: entry)
        try? await Task.sleep(nanoseconds: 50_000_000)

        expect(service.resumedEntry?.id == entry.id, "resumedEntry set on copy username")
        expect(didHidePalette, "Palette hide callback invoked")
        expect(shownMessage?.contains("sauravsz") == true, "Message confirms copied username")
        let pastedUsername = NSPasteboard.general.string(forType: .string)
        expect(pastedUsername == "sauravsz", "Username written to pasteboard")
    }

    static func testFilter() {
        let keychain = KeychainSecretStore(scope: "test.kpxc.\(UUID().uuidString)")
        let service = KeePassXCService(keychain: keychain)
        let entry = KeePassXCEntry(path: "Root/Logins/GitHub", title: "GitHub", username: "sauravsz", group: "Logins")

        service.entries = [
            entry,
            KeePassXCEntry(path: "Root/Work/Slack", title: "Slack", username: "sz_work", group: "Work"),
            KeePassXCEntry(path: "Root/Finance/Bank", title: "Bank Account", username: "sz_bank", group: "Finance")
        ]

        service.filterEntries(query: "git")
        expect(service.filteredEntries.count == 1, "Filter matches git")
        expect(service.filteredEntries.first?.title == "GitHub", "Filtered result is GitHub")

        service.filterEntries(query: "work")
        expect(service.filteredEntries.count == 1, "Filter matches group Work")
        expect(service.filteredEntries.first?.title == "Slack", "Filtered result is Slack")

        service.filterEntries(query: "")
        expect(service.filteredEntries.count == 3, "Empty filter shows all entries")
    }
}
