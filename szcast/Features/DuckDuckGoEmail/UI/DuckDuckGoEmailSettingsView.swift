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
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DuckDuckGo Email Protection")
                            .font(.headline)
                        Text("Generate private @duck.com forwarding addresses that strip tracker scripts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                LabeledContent {
                    HStack(spacing: 8) {
                        SecureField("Bearer token", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)

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
                } label: {
                    Text("API token")
                    Text(statusMessage ?? (service.hasToken ? "Configured in macOS Keychain." : "Paste your Bearer token from duckduckgo.com/email."))
                }
            } header: {
                Text("Account & Token")
            } footer: {
                Text("Log into duckduckgo.com/email in your browser, open Network inspector, and copy the Bearer token.")
            }

            Section {
                LabeledContent {
                    Button(isGenerating ? "Generating…" : "Generate Test Alias") {
                        generateTestAlias()
                    }
                    .controlSize(.regular)
                    .disabled(!service.hasToken || isGenerating)
                } label: {
                    Text("Test alias generator")
                    Text("Verifies token and copies a new @duck.com alias to your clipboard.")
                }

                LabeledContent {
                    Text("Hyper + D  (⌃⌥⇧⌘D)")
                        .font(.subheadline.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Global shortcut")
                    Text("Generate and copy a fresh @duck.com alias anywhere.")
                }
            } header: {
                Text("Shortcuts & Testing")
            }
        }
        .formStyle(.grouped)
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
