import SwiftUI

@MainActor
@Observable
final class SnippetFolderConfigState {
    let isCreating: Bool
    let parentPath: String?
    var name: String
    var keywordPrefix: String
    var icon: String
    var isEnabled: Bool

    init(
        isCreating: Bool,
        parentPath: String? = nil,
        name: String = "",
        keywordPrefix: String = "",
        icon: String = "",
        isEnabled: Bool = true
    ) {
        self.isCreating = isCreating
        self.parentPath = parentPath
        self.name = name
        self.keywordPrefix = keywordPrefix
        self.icon = icon
        self.isEnabled = isEnabled
    }
}

struct SnippetFolderConfigField: View {
    @Environment(\.metrics) private var metrics
    @Bindable var state: SnippetFolderConfigState
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text("Folder Name")
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                TextField(
                    "", text: $state.name,
                    prompt: Text("e.g. Work, Code, Email").foregroundStyle(Theme.Colors.textTertiary)
                )
                .dialogTextField()
                .focused($nameFocused)
                .onAppear { nameFocused = true }
            }

            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text("Keyword Prefix")
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                TextField(
                    "", text: $state.keywordPrefix,
                    prompt: Text("Optional, e.g. !g").foregroundStyle(Theme.Colors.textTertiary)
                )
                .dialogTextField()
            }

            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text("Icon")
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                HStack(spacing: metrics.spacing.sm) {
                    SnippetFolderIconView(icon: state.icon.isEmpty ? nil : state.icon, size: 22)
                    TextField(
                        "", text: $state.icon,
                        prompt: Text("SF Symbol, emoji, or domain").foregroundStyle(Theme.Colors.textTertiary)
                    )
                    .dialogTextField()
                }
            }

            Toggle(isOn: $state.isEnabled) {
                Text("Enabled")
                    .font(metrics.typography.rowTitle)
            }
            .toggleStyle(.checkbox)
        }
    }
}
