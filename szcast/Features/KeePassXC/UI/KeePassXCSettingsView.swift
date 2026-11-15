import AppKit
import SwiftUI

struct KeePassXCSettingsView: View {
    @State private var service = KeePassXCService()
    @State private var databasePath: String = ""
    @State private var keyfilePath: String = ""
    @State private var customCliPath: String = ""
    @State private var passwordInput: String = ""
    @State private var statusMessage: String?
    @AppStorage("keepassxc.windowResumption") private var windowResumptionEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KeePassXC Password Manager")
                            .font(.headline)
                        Text("Offline credentials and TOTP retrieval via keepassxc-cli with macOS Keychain storage.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                LabeledContent {
                    HStack(spacing: 8) {
                        Text(databasePath.isEmpty ? "No database chosen" : databasePath)
                            .font(.subheadline)
                            .foregroundStyle(databasePath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Browse…") {
                            browseForDatabase()
                        }
                        .controlSize(.regular)
                    }
                } label: {
                    Text("Database (.kdbx)")
                    Text("Path to your KeePassXC password database.")
                }

                LabeledContent {
                    HStack(spacing: 8) {
                        Text(keyfilePath.isEmpty ? "None" : keyfilePath)
                            .font(.subheadline)
                            .foregroundStyle(keyfilePath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Browse…") {
                            browseForKeyfile()
                        }
                        .controlSize(.regular)

                        if !keyfilePath.isEmpty {
                            Button("Clear") {
                                keyfilePath = ""
                                service.keyfilePath = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }
                } label: {
                    Text("Keyfile (optional)")
                    Text("Optional encryption keyfile for database unlock.")
                }

                LabeledContent {
                    HStack(spacing: 8) {
                        SecureField("Master password", text: $passwordInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)

                        Button(service.isUnlocked ? "Update" : "Save") {
                            service.masterPassword = passwordInput
                            statusMessage = "Saved to Keychain."
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(passwordInput.isEmpty)

                        if service.isUnlocked {
                            Button("Clear") {
                                service.masterPassword = nil
                                passwordInput = ""
                                statusMessage = "Removed."
                            }
                            .controlSize(.regular)
                        }
                    }
                } label: {
                    Text("Master password")
                    Text(statusMessage ?? (service.isUnlocked ? "Database unlocked in Keychain." : "Stored securely in Keychain for instant access."))
                }
            } header: {
                Text("Database & Credentials")
            }

            Section {
                LabeledContent {
                    Text(service.resolveCliPath() ?? "Not found (brew install keepassxc)")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(service.resolveCliPath() != nil ? Color.secondary : Color.red)
                } label: {
                    Text("CLI tool path")
                    Text("Executable used to read database entries.")
                }
            } header: {
                Text("CLI Integration")
            }

            Section {
                Toggle(isOn: $windowResumptionEnabled) {
                    Text("Persistent account resumption")
                    Text("Toggling szcast open again (⌥Space) immediately restores the active account view to copy additional fields.")
                }

                LabeledContent {
                    Text("⌘C")
                        .font(.subheadline.weight(.semibold).monospaced())
                } label: {
                    Text("Copy password")
                    Text("Copies secret and dismisses launcher.")
                }

                LabeledContent {
                    Text("⌘T")
                        .font(.subheadline.weight(.semibold).monospaced())
                } label: {
                    Text("Copy TOTP")
                    Text("Copies 2FA digits and dismisses launcher.")
                }

                LabeledContent {
                    Text("⌘B")
                        .font(.subheadline.weight(.semibold).monospaced())
                } label: {
                    Text("Copy username")
                    Text("Copies account username or email.")
                }

                LabeledContent {
                    Text("⌘U")
                        .font(.subheadline.weight(.semibold).monospaced())
                } label: {
                    Text("Open URL")
                    Text("Opens entry website in default browser.")
                }

                LabeledContent {
                    Text("Esc")
                        .font(.subheadline.weight(.semibold).monospaced())
                } label: {
                    Text("Return to list")
                    Text("Goes back to accounts search list.")
                }
            } header: {
                Text("Account Shortcuts & Resumption")
            }
        }
        .formStyle(.grouped)
        .task {
            databasePath = service.databasePath
            keyfilePath = service.keyfilePath
            customCliPath = service.customCliPath
            if service.isUnlocked {
                passwordInput = service.masterPassword ?? ""
            }
        }
    }

    private func browseForDatabase() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "kdbx") ?? .data]
        panel.prompt = "Choose Database"

        if panel.runModal() == .OK, let url = panel.url {
            databasePath = url.path
            service.databasePath = url.path
        }
    }

    private func browseForKeyfile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Keyfile"

        if panel.runModal() == .OK, let url = panel.url {
            keyfilePath = url.path
            service.keyfilePath = url.path
        }
    }
}
