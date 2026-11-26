import AppKit
import SwiftUI

struct AISettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AISettingsStore.self) private var settings
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $appSettings.aiEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .aiAI, title: "Enable AI",
                        subtitle: "Nothing is loaded or sent while it is off.")
                }
            } header: {
                SettingsSectionHeader(.aiAI)
            }

            FeatureCommandsSection(owner: .ai, anchor: .aiCommands)
                .settingsEnabled(appSettings.aiEnabled)

            Group {
                chatSection
                conversationsSection
                systemPromptSection
                ChatPresetsSection()
                MCPSettingsSection()
            }
            .settingsEnabled(appSettings.aiEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.ai)
        .onAppear {
            core.applyInstalledAILifecycle()
        }
        // Switched on with the pane already open, provider status would otherwise stay empty.
        .onChange(of: appSettings.aiEnabled) { core.applyInstalledAILifecycle() }
    }

    private var chatSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.webSearchEnabled) {
                SettingsRowTitle(.aiChat, "Web search")
                Text("Prompts query the web for real-time citations and context.")
            }
            if settings.webSearchEnabled {
                Picker(selection: $settings.webSearchProvider) {
                    ForEach(WebSearchProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                } label: {
                    SettingsRowTitle(.aiChat, "Search engine")
                }
                WebSearchAPIKeyRow(provider: settings.webSearchProvider)
            }
            Toggle(isOn: $settings.choicesEnabled) {
                SettingsRowTitle(.aiChat, "Suggested replies")
                Text("Next steps the model offers as buttons after a reply.")
            }
            Toggle(isOn: $settings.expandsReasoning) {
                SettingsRowTitle(.aiChat, "Expand thinking")
                Text("Thinking blocks start expanded instead of collapsed.")
            }
            Picker(selection: $settings.toolRounds) {
                ForEach(AIToolRounds.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiChat, "Tool call rounds")
                Text(
                    """
                    A reply stops after this many; Unlimited runs until Stop. API connections, Codex \
                    and Claude.
                    """)
            }
            Stepper(value: $settings.chatFontSize, in: 10...24, step: 1) {
                SettingsRowTitle(.aiChat, "Chat font size")
                Text("\(Int(settings.chatFontSize)) pt (default: 14 pt)")
            }
            Picker(selection: $settings.chatFontFamily) {
                Text("System Default").tag(nil as String?)
                ForEach(availableFontFamilies, id: \.self) { family in
                    Text(family).tag(Optional(family))
                }
            } label: {
                SettingsRowTitle(.aiChat, "Chat font")
            }
            Picker(selection: $settings.chatCodeFontFamily) {
                Text("System Monospaced").tag(nil as String?)
                ForEach(availableMonospacedFontFamilies, id: \.self) { family in
                    Text(family).tag(Optional(family))
                }
            } label: {
                SettingsRowTitle(.aiChat, "Code font")
            }
            ChatTypographyPreview(
                fontSize: settings.chatFontSize,
                fontFamily: settings.chatFontFamily,
                codeFontFamily: settings.chatCodeFontFamily
            )
        } header: {
            SettingsSectionHeader(.aiChat)
        }
    }

    private var availableFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    private var availableMonospacedFontFamilies: [String] {
        let manager = NSFontManager.shared
        let mono = manager.availableFontFamilies.filter { family in
            if let font = NSFont(name: family, size: 12) {
                return manager.traits(of: font).contains(.fixedPitchFontMask)
            }
            return manager.font(withFamily: family, traits: .fixedPitchFontMask, weight: 5, size: 12) != nil
        }
        return mono.isEmpty ? ["Menlo", "Monaco", "Courier New"] : mono.sorted()
    }

    private var conversationsSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.opensTo) {
                ForEach(AIOpensTo.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Opens to")
                Text("What Quick AI and the AI Chat window show when you open them.")
            }
            if settings.opensTo == .recent {
                Picker(selection: $settings.newChatAfter) {
                    ForEach(AINewChatAfter.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.aiConversations, "Start a new conversation after")
                }
            }
            Picker(selection: $settings.retention) {
                ForEach(AIRetention.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Keep conversations")
                Text("Older ones are deleted, except pinned chats.")
            }
        } header: {
            SettingsSectionHeader(.aiConversations)
        } footer: {
            Text("Conversations stay on this Mac, outside settings backups.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var systemPromptSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.systemPromptEnabled) {
                SettingsRowTitle(.aiSystemPrompt, "Send a system prompt")
                Text("Off also skips szcast's own prompt.")
            }
            SystemPromptEditor(text: $settings.systemPrompt)
                .settingsEnabled(settings.systemPromptEnabled)
        } header: {
            SettingsSectionHeader(.aiSystemPrompt)
        } footer: {
            Text("Sent before every message, after szcast's own. Both are billed each turn.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WebSearchAPIKeyRow: View {
    let provider: WebSearchProvider
    @Environment(AISettingsStore.self) private var settings
    @State private var apiKey: String = ""
    @State private var isStored: Bool = false

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                RevealableSecureField(
                    title: String(localized: "\(provider.title) API Key"),
                    text: $apiKey,
                    prompt: Text(provider.placeholder)
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(minWidth: 160)

                if isStored && apiKey.isEmpty {
                    Button("Clear") {
                        settings.setWebSearchAPIKey("", for: provider)
                        isStored = false
                        apiKey = ""
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Save") {
                        settings.setWebSearchAPIKey(apiKey, for: provider)
                        isStored = true
                        apiKey = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } label: {
            SettingsRowTitle(.aiChat, "\(provider.title) API key")
            if isStored {
                Text("Stored securely in Keychain.")
            } else {
                Text("Required for live web search.")
            }
        }
        .onAppear { refresh() }
        .onChange(of: provider) { refresh() }
    }

    private func refresh() {
        isStored = settings.hasWebSearchAPIKey(for: provider)
        apiKey = ""
    }
}

private struct ChatTypographyPreview: View {
    let fontSize: CGFloat
    let fontFamily: String?
    let codeFontFamily: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Heading 2 Preview")
                    .font(previewFont(size: (fontSize * 1.15).rounded(), weight: .semibold))
                Text("This is how your AI chat assistant responses will look with styled text.")
                    .font(previewFont(size: fontSize, weight: .regular))
                Text("let code = \"preview\";")
                    .font(previewCodeFont(size: max(fontSize - 1, 9)))
                    .padding(Theme.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.Colors.controlSurface)
                    )
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface.opacity(0.5))
            )
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func previewFont(size: CGFloat, weight: Font.Weight) -> Font {
        if let fontFamily, !fontFamily.isEmpty {
            return .custom(fontFamily, size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    private func previewCodeFont(size: CGFloat) -> Font {
        if let codeFontFamily, !codeFontFamily.isEmpty {
            return .custom(codeFontFamily, size: size)
        }
        return .system(size: size, design: .monospaced)
    }
}
