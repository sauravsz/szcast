import AppKit
import SwiftUI

struct DuckDuckGoEmailSettingsView: View {
    @State private var service = DuckDuckGoEmailService()
    @State private var tokenInput: String = ""
    @State private var statusMessage: String?
    @State private var isGenerating: Bool = false
    @State private var isSaved: Bool = false

    var body: some View {
        Form {
            Section {
                SettingsRow(
                    title: "DuckDuckGo Email Protection",
                    subtitle: "Generate private @duck.com forwarding addresses that strip tracker scripts."
                ) {
                    SettingsTabIcon(
                        systemImage: "envelope.badge.shield.half.filled",
                        tint: .accentColor,
                        size: Theme.Size.settingsRowIcon * 1.5
                    )
                } trailing: {
                    Button(isGenerating ? "Generating…" : "Generate Test") {
                        generateTestAlias()
                    }
                    .controlSize(.regular)
                    .disabled(!service.hasToken || isGenerating)
                }

                SettingsRow(
                    title: "Bearer Token",
                    subtitle: statusMessage ?? (service.hasToken ? "Configured in macOS Keychain." : "Paste your Bearer token from duckduckgo.com/email.")
                ) {
                    HStack(spacing: 8) {
                        SecureField("Bearer token", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)

                        Button(service.hasToken ? "Update" : "Save") {
                            service.token = tokenInput
                            isSaved = true
                            statusMessage = "Saved to Keychain."
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if service.hasToken {
                            Button("Clear") {
                                service.token = nil
                                tokenInput = ""
                                statusMessage = "Removed."
                            }
                            .controlSize(.regular)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.duckDuckGoEmailAccount)
            } footer: {
                Text("Log into duckduckgo.com/email in your browser, open Network inspector, and copy the Bearer token.")
            }

            FeatureCommandsSection(owner: .duckDuckGoEmail, anchor: .duckDuckGoEmailCommands)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.duckDuckGoEmail)
        .task {
            if let saved = service.token {
                tokenInput = saved
            }
        }
    }

    private func generateTestAlias() {
        isGenerating = true
        statusMessage = nil
        Task {
            do {
                let address = try await service.generateAlias()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
                statusMessage = "Created and copied: \(address)"
            } catch {
                statusMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
