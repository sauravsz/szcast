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
                SettingsRow(
                    title: "Ente Auth 2FA Authenticator",
                    subtitle: "Offline RFC 6238 TOTP generator. Auto-loads accounts and generates 6-digit codes."
                ) {
                    SettingsTabIcon(
                        systemImage: "key.fill",
                        tint: .accentColor,
                        size: Theme.Size.settingsRowIcon * 1.5
                    )
                } trailing: {
                    Button("Paste URI…") {
                        showingManualInputSheet = true
                    }
                    .controlSize(.regular)
                }

                SettingsRow(
                    title: "Export file",
                    subtitle: exportPath.isEmpty ? "No export file selected" : exportPath
                ) {
                    Button("Browse…") {
                        browseForExport()
                    }
                    .controlSize(.regular)
                }

                SettingsRow(
                    title: "Import secrets",
                    subtitle: importStatus ?? "Import accounts from decrypted ente_auth.txt file."
                ) {
                    Button("Import / Refresh") {
                        let url = exportPath.isEmpty ? nil : URL(fileURLWithPath: exportPath)
                        let res = store.importSecrets(from: url)
                        importStatus = res.message
                        store.loadAccounts()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            } header: {
                SettingsSectionHeader(.enteAuthEnteAuth)
            }

            FeatureCommandsSection(owner: .enteAuth, anchor: .enteAuthCommands)

            Section {
                if store.accounts.isEmpty {
                    Text("No 2FA accounts imported yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                } else {
                    ForEach(store.accounts) { account in
                        SettingsRow(
                            title: account.issuer,
                            subtitle: account.username
                        ) {
                            Image(systemName: "person.badge.key.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: SettingsListMetrics.iconSize)
                        } trailing: {
                            Text("\(account.digits) digits · \(account.period)s")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 8)
                            Button(role: .destructive) {
                                store.deleteAccount(id: account.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Delete account")
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.enteAuthAccounts)
            } footer: {
                Text("Data is stored encrypted with owner-only (0600) permissions in Application Support/szcast/EnteAuth.")
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.enteAuth)
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
