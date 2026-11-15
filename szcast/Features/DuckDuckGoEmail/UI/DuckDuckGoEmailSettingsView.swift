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
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("DuckDuckGo Email Protection")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Generate private @duck.com forwarding addresses that strip email trackers.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("DuckDuckGo API Token")
                            .font(.system(size: 12, weight: .medium))

                        HStack(spacing: 8) {
                            SecureField("Enter your DuckDuckGo Bearer token", text: $tokenInput)
                                .textFieldStyle(.roundedBorder)

                            Button(service.hasToken ? "Update" : "Save") {
                                service.token = tokenInput
                                isSaved = true
                                statusMessage = "Token saved to macOS Keychain."
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if service.hasToken {
                                Button("Clear") {
                                    service.token = nil
                                    tokenInput = ""
                                    statusMessage = "Token removed."
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    if service.hasToken {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("API token is configured in Keychain.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let msg = statusMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundStyle(msg.contains("error") || msg.contains("removed") ? Color.orange : Color.green)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Account & Token")
            } footer: {
                Text("To get your token: Log into duckduckgo.com/email in your browser, open Web Inspector Network tab, and copy the Bearer token from the addresses API request.")
            }

            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test Alias Generator")
                                .font(.system(size: 12, weight: .medium))
                            Text("Test token and generate a fresh @duck.com address directly to clipboard.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(isGenerating ? "Generating…" : "Generate Test Alias") {
                            generateTestAlias()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!service.hasToken || isGenerating)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Testing & Verification")
            }

            Section {
                HStack(spacing: 12) {
                    Text("Generate & Copy Duck Address")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("Hyper + D  (⌃⌥⇧⌘D)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            } header: {
                Text("Global Hotkey")
            } footer: {
                Text("Press Hyper + D anywhere to instantly generate a new private email address and copy it to your clipboard.")
            }
        }
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
