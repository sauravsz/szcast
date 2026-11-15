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
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("KeePassXC Password Manager")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Pure offline password & TOTP retrieval wrapping keepassxc-cli with Keychain security.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    LabeledContent("Database (.kdbx)") {
                        HStack(spacing: 8) {
                            Text(databasePath.isEmpty ? "No database chosen" : databasePath)
                                .font(.system(size: 11))
                                .foregroundStyle(databasePath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 240, alignment: .trailing)

                            Button("Browse…") {
                                browseForDatabase()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    LabeledContent("Keyfile (optional)") {
                        HStack(spacing: 8) {
                            Text(keyfilePath.isEmpty ? "None" : keyfilePath)
                                .font(.system(size: 11))
                                .foregroundStyle(keyfilePath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 240, alignment: .trailing)

                            Button("Browse…") {
                                browseForKeyfile()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if !keyfilePath.isEmpty {
                                Button("Clear") {
                                    keyfilePath = ""
                                    service.keyfilePath = ""
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Master Password")
                            .font(.system(size: 12, weight: .medium))

                        HStack(spacing: 8) {
                            SecureField("Enter master password for automatic unlock", text: $passwordInput)
                                .textFieldStyle(.roundedBorder)

                            Button(service.isUnlocked ? "Update" : "Save") {
                                service.masterPassword = passwordInput
                                statusMessage = "Master password stored securely in Keychain."
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(passwordInput.isEmpty)

                            if service.isUnlocked {
                                Button("Clear") {
                                    service.masterPassword = nil
                                    passwordInput = ""
                                    statusMessage = "Master password removed from Keychain."
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    if service.isUnlocked {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Database unlocked and cached in Keychain.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let msg = statusMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundStyle(msg.contains("removed") ? Color.orange : Color.green)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Database & Credentials")
            }

            Section {
                LabeledContent("keepassxc-cli path") {
                    Text(service.resolveCliPath() ?? "Not found (Install via 'brew install keepassxc')")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(service.resolveCliPath() != nil ? Color.primary : Color.red)
                }
            } header: {
                Text("CLI Integration")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Persistent Account Window Resumption", isOn: $windowResumptionEnabled)
                        .font(.system(size: 12, weight: .medium))
                    Text("When you copy a field, szcast hides itself. Toggling szcast open again (⌥Space) immediately restores the exact same account view so you can copy the password, TOTP, or username without re-searching.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("In-View Keyboard Shortcuts")
                        .font(.system(size: 12, weight: .semibold))

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("⌘C")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("Copy Password & hide palette")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("⌘T")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("Copy TOTP Code & hide palette")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("⌘B")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("Copy Username & hide palette")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("⌘U")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("Open Account URL in default browser")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("Esc")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("Return to account search list")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Shortcuts & Resumption")
            }
        }
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
