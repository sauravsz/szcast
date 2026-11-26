import SwiftUI

struct SnippetEditorView: View {
    @Bindable var editor: SnippetEditorSession
    let openMenuCorner: MenuPanelCorner?
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    @Environment(SnippetCoordinator.self) private var coordinator
    @Environment(SnippetsStore.self) private var store
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @State private var focusedField: SnippetEditorSession.Field?
    @FocusState private var focusedControl: SnippetEditorSession.Field?
    @State private var placeholderMenuFrame: CGRect = .zero
    @State private var folderMenuFrame: CGRect = .zero

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: metrics.spacing.xxl) {
                templateEditor
                properties
            }
            .padding(.horizontal, metrics.spacing.xxxl * 2)
            .padding(.vertical, metrics.spacing.md)
        }
        .scrollClipDisabled()
        .edgeDissolve()
        .disabled(editor.isSaving)
        .focusEffectDisabled()
        .task(id: palette.focusToken) {
            palette.noteEditingField(true)
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedField = editor.focusedField
        }
        .task(id: editor.isSaving) {
            if editor.isSaving { await coordinator.saveSnippet(editor) }
        }
        .onChange(of: editor.focusedField) { _, field in focusedField = field }
        .onChange(of: focusedField) { _, field in
            if let field { editor.focusedField = field }
            focusedControl = (field == .folder || field == .enabled || field == .confirmation)
                ? field : nil
        }
        .onChange(of: focusedControl) { _, field in
            if let field { focusedField = field }
        }
        .onDisappear {
            coordinator.editorDidClose(editor)
            palette.noteEditingField(false)
        }
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            fieldTitle(String(localized: "Snippet"))
            VStack(spacing: metrics.spacing.xs) {
                FormTextArea(
                    text: $editor.text, selection: $editor.selection, focused: focusBinding(.template),
                    minimumHeight: metrics.size.panelHeight - metrics.size.textAreaUnit * 4
                        - metrics.spacing.xl - metrics.spacing.md * 2 - metrics.spacing.xs
                        - metrics.typography.textNSFont(.callout).boundingRectForFont.height,
                    label: String(localized: "Snippet template"), moveFocus: editor.advanceFocus
                )
                .accessibilityHint("Enter the text szcast expands.")
                HStack {
                    placeholderMenu
                    Spacer()
                }
                .padding(.horizontal, metrics.spacing.xl)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .zIndex(1)
            }
            .padding(.bottom, metrics.spacing.md)
            .formFieldChrome(focused: focusedField == .template)
            Text("Use placeholders for the clipboard, current date, arguments and more.")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholderMenuCorner: MenuPanelCorner {
        .belowControl(placeholderMenuFrame, trailing: false)
    }

    private var placeholderMenu: some View {
        PlaceholderMenuButton(
            isOpen: openMenuCorner == placeholderMenuCorner, frame: $placeholderMenuFrame,
            action: showPlaceholderMenu)
    }

    private func showPlaceholderMenu() {
        let insertionSelection = editor.selection
        let groups: [(title: String, tokens: [String])] = [
            (String(localized: "Text"), ["{cursor}", "{clipboard}", "{selection}", "{uuid}"]),
            (String(localized: "Date & Time"), ["{date}", "{time}", "{datetime}", "{day}"]),
            (String(localized: "Arguments"), ["{argument name=\"Name\"}"]),
            (String(localized: "Snippets"), ["{snippet name=\"Name\"}"])
        ]
        let items = groups.flatMap { group in
            group.tokens.enumerated().map { index, token in
                PopoverMenuItem(
                    title: token, icon: .blank, sectionTitle: index == 0 ? group.title : nil,
                    startsSection: index == 0
                ) {
                    editor.selection = insertionSelection
                    editor.insert(token)
                    focusedField = .template
                }
            }
        }
        openInputMenu(PopoverMenuContent(items: items), placeholderMenuCorner, 0)
    }

    private var folderMenuCorner: MenuPanelCorner {
        .belowControl(folderMenuFrame, trailing: false)
    }

    private var effectiveKeywordPreview: String? {
        let trimmedFolder = editor.folder.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = store.effectivePrefix(for: trimmedFolder.isEmpty ? nil : trimmedFolder)
        guard !prefix.isEmpty else { return nil }
        let trimmedKeyword = editor.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedKeyword.isEmpty ? prefix : prefix + trimmedKeyword
    }

    private func showFolderMenu() {
        let isRootSelected = editor.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: String(localized: "None (Root)"),
                systemImage: isRootSelected ? "checkmark" : "tray"
            ) {
                editor.folder = ""
                focusedField = .folder
            }
        ]
        for folder in store.folders {
            let displayTitle = folder.path.split(separator: "/").joined(separator: " / ")
            items.append(
                PopoverMenuItem(
                    title: displayTitle,
                    systemImage: editor.folder == folder.path ? "checkmark" : "folder"
                ) {
                    editor.folder = folder.path
                    focusedField = .folder
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "New Folder…"),
                systemImage: "folder.badge.plus",
                startsSection: true
            ) {
                let parent = editor.folder.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    if let created = await coordinator.createFolder(
                        parentPath: parent.isEmpty ? nil : parent)
                    {
                        editor.folder = created.path
                    }
                    focusedField = .folder
                }
            })
        openInputMenu(PopoverMenuContent(items: items), folderMenuCorner, 0)
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
            field(
                String(localized: "Name"), placeholder: String(localized: "Snippet name"),
                label: String(localized: "Snippet name"), text: $editor.name,
                focus: .name,
                hint: String(localized: "Required. Shown in the library and launcher."))
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                fieldTitle(String(localized: "Folder"))
                Button(action: showFolderMenu) {
                    HStack(spacing: metrics.spacing.sm) {
                        Image(systemName: editor.folder.isEmpty ? "tray" : "folder.fill")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(
                            editor.folder.isEmpty
                                ? String(localized: "None (Root)")
                                : editor.folder.split(separator: "/").joined(separator: " / ")
                        )
                        .foregroundStyle(
                            editor.folder.isEmpty ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(.horizontal, metrics.spacing.md)
                    .frame(height: metrics.size.dialogButtonHeight)
                    .formFieldChrome(focused: focusedField == .folder)
                }
                .buttonStyle(.plain)
                .focusable()
                .focused($focusedControl, equals: .folder)
                .onKeyPress(.space) {
                    showFolderMenu()
                    return .handled
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    folderMenuFrame = $0
                }
                .accessibilityLabel(String(localized: "Snippet folder"))
                .accessibilityHint(String(localized: "Optional. Organize snippets inside folders."))
            }
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                field(
                    String(localized: "Keyword"), placeholder: String(localized: "Optional, for example !notes"),
                    label: String(localized: "Snippet keyword"), text: $editor.keyword,
                    focus: .keyword, hint: String(localized: "Optional. Type this to expand the snippet.")
                )
                if let preview = effectiveKeywordPreview {
                    Text(
                        editor.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? String(localized: "Folder prefix “\(preview)” will be prepended.")
                            : String(localized: "Expands on “\(preview)”")
                    )
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                fieldTitle(String(localized: "Icon / Favicon"))
                HStack(spacing: metrics.spacing.md) {
                    EntryIconView(source: SnippetFaviconService.resolveIcon(for: editor.snippet))
                        .frame(width: 24, height: 24)

                    FormTextInput(
                        text: $editor.icon, focused: focusBinding(.icon),
                        placeholder: String(localized: "Domain (e.g. github.com), SF Symbol, or URL"),
                        label: String(localized: "Snippet icon"), moveFocus: editor.advanceFocus
                    )
                }
                .padding(.leading, metrics.spacing.sm)
                .frame(height: metrics.size.dialogButtonHeight)
                .formFieldChrome(focused: focusedField == .icon)
                .accessibilityHint(String(localized: "Optional custom favicon domain, URL, or SF Symbol."))
            }
            option(
                String(localized: "Enabled"),
                detail: String(localized: "Disabled snippets cannot be expanded."),
                value: $editor.isEnabled, focus: .enabled)
            option(
                String(localized: "Show confirmation"),
                detail: String(localized: "Confirm on screen after this snippet is inserted."),
                value: $editor.showsConfirmation, focus: .confirmation)
            if let errorMessage = editor.errorMessage {
                Text(errorMessage)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .font(metrics.typography.rowTitle)
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private func field(
        _ title: String, placeholder: String, label: String, text: Binding<String>,
        focus: SnippetEditorSession.Field, hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            fieldTitle(title)
            FormTextInput(
                text: text, focused: focusBinding(focus), placeholder: placeholder,
                label: label, moveFocus: editor.advanceFocus
            )
            .frame(height: metrics.size.dialogButtonHeight)
            .formFieldChrome(focused: focusedField == focus)
            .accessibilityHint(hint)
        }
    }

    private func focusBinding(_ field: SnippetEditorSession.Field) -> Binding<Bool> {
        Binding(
            get: { focusedField == field },
            set: { value in
                if value { focusedField = field } else if focusedField == field { focusedField = nil }
            })
    }

    private func option(
        _ title: String, detail: String, value: Binding<Bool>, focus: SnippetEditorSession.Field
    ) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(title)
                Text(detail)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .focusable()
        .focused($focusedControl, equals: focus)
        .onKeyPress(.space) {
            value.wrappedValue.toggle()
            return .handled
        }
    }
}
