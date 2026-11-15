import AppKit
import SwiftUI

struct EnteAuthSettingsView: View {
    @State private var store = EnteAuthStore()
    @State private var exportPath: String = ""
    @State private var importStatus: String?
    @State private var showingManualInputSheet = false
    @State private var manualText = ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ente Auth 2FA Authenticator")
                            .font(.headline)
                        Text("Offline RFC 6238 TOTP generator. Press Hyper + T (⌃⌥⇧⌘T) to search and copy codes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                LabeledContent {
                    HStack(spacing: 8) {
                        Text(exportPath.isEmpty ? "No export file selected" : exportPath)
                            .font(.subheadline)
                            .foregroundStyle(exportPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Browse…") {
                            browseForExport()
                        }
                        .controlSize(.regular)
                    }
                } label: {
                    Text("Export file")
                    Text("Path to decrypted ente_auth.txt file.")
                }

                LabeledContent {
                    HStack(spacing: 8) {
                        Button("Import / Refresh") {
                            let url = exportPath.isEmpty ? nil : URL(fileURLWithPath: exportPath)
                            let res = store.importSecrets(from: url)
                            importStatus = res.message
                            store.loadAccounts()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                        Button("Paste URI…") {
                            showingManualInputSheet = true
                        }
                        .controlSize(.regular)
                    }
                } label: {
                    Text("Import secrets")
                    Text(importStatus ?? "Import accounts from file or otpauth:// URI.")
                }
            } header: {
                Text("Ente Auth Integration")
            }

            Section {
                if store.accounts.isEmpty {
                    Text("No 2FA accounts imported yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                } else {
                    ForEach(store.accounts) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.issuer)
                                    .font(.headline)
                                Text(account.username)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(account.digits) digits · \(account.period)s")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                store.deleteAccount(id: account.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Delete account")
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Imported Accounts (\(store.accounts.count))")
            } footer: {
                Text("Data is stored encrypted with owner-only (0600) permissions in Application Support/szcast/EnteAuth.")
            }

            Section {
                LabeledContent {
                    Text("Hyper + T  (⌃⌥⇧⌘T)")
                        .font(.subheadline.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Global shortcut")
                    Text("Search accounts and copy TOTP code directly on Return.")
                }
            } header: {
                Text("Shortcuts")
            }
        }
        .formStyle(.grouped)
        .task {
            store.loadAccounts()
            if let detected = store.findExportFile() {
                exportPath = detected.path
            }
        }
        .sheet(isPresented: $showingManualInputSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import otpauth:// URIs")
                    .font(.headline)
                Text("Paste one or more otpauth://totp/ URIs exported from your authenticator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $manualText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 440, height: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingManualInputSheet = false
                        manualText = ""
                    }
                    Button("Import") {
                        let lines = manualText.components(separatedBy: .newlines)
                        var count = 0
                        for line in lines {
                            if let acc = EnteAuthStore.parseOTPAuthURI(line) {
                                store.addAccount(acc)
                                count += 1
                            }
                        }
                        importStatus = "Imported \(count) account(s)."
                        store.loadAccounts()
                        showingManualInputSheet = false
                        manualText = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
    }

    private func browseForExport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        panel.prompt = "Choose Export File"

        if panel.runModal() == .OK, let url = panel.url {
            exportPath = url.path
            let res = store.importSecrets(from: url)
            importStatus = res.message
            store.loadAccounts()
        }
    }
}
