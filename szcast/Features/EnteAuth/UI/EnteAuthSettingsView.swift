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
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ente Auth 2FA Authenticator")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Offline RFC 6238 TOTP generator. Press Hyper + T (⌃⌥⇧⌘T) to search and copy codes.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    LabeledContent("Export file path") {
                        HStack(spacing: 8) {
                            Text(exportPath.isEmpty ? "No export file found" : exportPath)
                                .font(.system(size: 11))
                                .foregroundStyle(exportPath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 240, alignment: .trailing)

                            Button("Browse…") {
                                browseForExport()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Import / Refresh Accounts") {
                            let url = exportPath.isEmpty ? nil : URL(fileURLWithPath: exportPath)
                            let res = store.importSecrets(from: url)
                            importStatus = res.message
                            store.loadAccounts()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Paste otpauth URI…") {
                            showingManualInputSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let status = importStatus {
                        Text(status)
                            .font(.system(size: 11))
                            .foregroundStyle(status.contains("Successfully") ? Color.green : Color.orange)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Ente Auth Integration")
            }

            Section {
                if store.accounts.isEmpty {
                    Text("No 2FA accounts imported yet. Click 'Browse' to select your ente_auth.txt export file.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(store.accounts) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.issuer)
                                    .font(.system(size: 13, weight: .medium))
                                Text(account.username)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(account.digits) digits · \(account.period)s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Button {
                                store.deleteAccount(id: account.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
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
                HStack(spacing: 12) {
                    Text("Global Hotkey")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("Hyper + T  (⌃⌥⇧⌘T)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            } header: {
                Text("Shortcuts")
            }
        }
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
