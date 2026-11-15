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
                SettingsRow(
                    title: "KeePassXC Password Manager",
                    subtitle: "Offline credentials and TOTP retrieval via keepassxc-cli with macOS Keychain storage."
                ) {
                    SettingsTabIcon(
                        systemImage: "lock.fill",
                        tint: .accentColor,
                        size: Theme.Size.settingsRowIcon * 1.5
                    )
                } trailing: {
                    EmptyView()
                }

                SettingsRow(
                    title: "Database (.kdbx)",
                    subtitle: databasePath.isEmpty ? "No database chosen" : databasePath
                ) {
                    Button("Browse…") {
                        browseForDatabase()
                    }
                    .controlSize(.regular)
                }

                SettingsRow(
                    title: "Keyfile (optional)",
                    subtitle: keyfilePath.isEmpty ? "None" : keyfilePath
                ) {
                    HStack(spacing: 8) {
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
                }

                SettingsRow(
                    title: "Master password",
                    subtitle: statusMessage ?? (service.isUnlocked ? "Database unlocked in Keychain." : "Stored securely in Keychain for instant access.")
                ) {
                    HStack(spacing: 8) {
                        SecureField("Master password", text: $passwordInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)

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
                }

                Toggle(isOn: $windowResumptionEnabled) {
                    SettingsRowTitle(.keepassxcDatabase, "Window resumption")
                    Text("Reopening szcast (⌥Space) immediately restores your open entry.")
                }
            } header: {
                SettingsSectionHeader(.keepassxcDatabase)
            }

            FeatureCommandsSection(owner: .keepassxc, anchor: .keepassxcCommands)

            Section {
                SettingsRow(
                    title: "Copy Password",
                    subtitle: "Copies secret to clipboard and dismisses launcher."
                ) {
                    Image(systemName: "key")
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsListMetrics.iconSize)
                } trailing: {
                    Text("⌘C")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.controlSurface)
                        .clipShape(Capsule())
                }

                SettingsRow(
                    title: "Copy TOTP",
                    subtitle: "Copies 2FA digits and dismisses launcher."
                ) {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsListMetrics.iconSize)
                } trailing: {
                    Text("⌘T")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.controlSurface)
                        .clipShape(Capsule())
                }

                SettingsRow(
                    title: "Copy Username",
                    subtitle: "Copies account username or email."
                ) {
                    Image(systemName: "person")
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsListMetrics.iconSize)
                } trailing: {
                    Text("⌘B")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.controlSurface)
                        .clipShape(Capsule())
                }

                SettingsRow(
                    title: "Open URL",
                    subtitle: "Opens website in your default browser."
                ) {
                    Image(systemName: "safari")
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsListMetrics.iconSize)
                } trailing: {
                    Text("⌘U")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.controlSurface)
                        .clipShape(Capsule())
                }
            } header: {
                SettingsSectionHeader(.keepassxcKeePassXC)
            }

            Section {
                SettingsRow(
                    title: "CLI Binary Path",
                    subtitle: service.resolveCliPath() ?? "Not found (brew install keepassxc)"
                ) {
                    HStack(spacing: 8) {
                        TextField("/opt/homebrew/bin/keepassxc-cli", text: $customCliPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        Button("Apply") {
                            service.customCliPath = customCliPath
                        }
                        .controlSize(.regular)
                    }
                }
            } header: {
                Text("CLI Integration")
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.keepassxc)
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
        panel.allowedContentTypes = [.init(filenameExtension: "kdbx")].compactMap { $0 }
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
