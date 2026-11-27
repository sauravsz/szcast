import SwiftUI

private enum SnippetCollectionSelection: Hashable {
    case all
    case root
    case folder(String)

    var folderPath: String? {
        if case let .folder(path) = self { return path }
        return nil
    }
}

struct SnippetsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(SnippetCoordinator.self) private var coordinator
    @Environment(SnippetsStore.self) private var snippetsStore
    @Environment(AppSettings.self) private var settings
    @State private var selection: SnippetCollectionSelection = .all

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .snippetsSnippets,
                enableTitle: "Enable snippets",
                enableSubtitle: "Expand templates from the launcher or by keyword.",
                // Enabling is also keyword-expansion consent, so it uses the confirming setter.
                isEnabled: Binding(
                    get: { settings.snippetsEnabled },
                    set: { coordinator.setSnippetsEnabled($0) }),
                showsInLauncher: $settings.snippetsShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            if settings.snippetsEnabled, core.snippetListener.status == .needsAccessibility {
                Section {
                    LabeledContent {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    } label: {
                        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .frame(width: SettingsListMetrics.iconSize)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text("Keyword expansion needs Accessibility access")
                                    .foregroundStyle(.orange)
                                Text("Launcher search still works.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Group {
                Section {
                    Picker(selection: $settings.snippetsDefaultAction) {
                        ForEach(SnippetDefaultAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    } label: {
                        SettingsRowTitle(.snippetsSnippets, "Default action")
                        Text("↵ performs this action.")
                    }
                } header: {
                    SettingsSectionHeader(.snippetsSnippets)
                }

                FeatureCommandsSection(owner: .snippets, anchor: .snippetsCommands)
                library
                libraryNotices
            }
            .settingsEnabled(settings.snippetsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.snippets)
    }

    private var library: some View {
        Section {
            SnippetsLibraryBrowser(selection: $selection)
                .listRowInsets(EdgeInsets())

            LabeledContent {
                Button("New Folder…") {
                    Task {
                        if let created = await coordinator.createFolder(parentPath: selection.folderPath) {
                            selection = .folder(created.path)
                        }
                    }
                }
                Button("Add…") {
                    coordinator.editSnippet(nil, initialFolder: selection.folderPath)
                }
            } label: {
                SettingsRowTitle(.snippetsLibrary, "New Snippet")
            }

            LabeledContent {
                if settings.snippetsFolder != nil {
                    Button(
                        String(localized: "snippets-use-default-folder", defaultValue: "Use Default"),
                        action: coordinator.resetSnippetsFolder)
                }
                Button("Choose…", action: coordinator.chooseSnippetsFolder)
                Button("Open Folder", action: coordinator.revealSnippetsInFinder)
                    .accessibilityHint("Reveals the snippets folder in Finder.")
            } label: {
                SettingsRowTitle(.snippetsLibrary, "Snippets Folder")
                Text((snippetsStore.snippetsDirectory.path as NSString).abbreviatingWithTildeInPath)
            }
        } header: {
            SettingsSectionHeader(.snippetsLibrary)
        }
    }

    @ViewBuilder
    private var libraryNotices: some View {
        if case .failed(let message) = snippetsStore.state {
            noticeSection(
                String(localized: "Couldn’t load the snippet library"), message, tint: .orange,
                retryHint: String(localized: "Tries to load the snippet library again."))
        }

        if !snippetsStore.issues.isEmpty {
            noticeSection(
                snippetIssueTitle, snippetIssueMessage, tint: .orange,
                retryHint: String(localized: "Reloads snippet files after you fix them on disk."))
        }

        if let operationError = snippetsStore.operationError {
            noticeSection(
                String(localized: "The snippet operation failed"), operationError, tint: .red,
                retryHint: nil)
        }
    }

    private func noticeSection(
        _ title: String, _ message: String, tint: Color, retryHint: String?
    ) -> some View {
        Section {
            LabeledContent {
                if let retryHint {
                    Button("Retry", action: snippetsStore.retry)
                        .accessibilityHint(retryHint)
                }
            } label: {
                Label(title, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(tint)
                Text(message)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var snippetIssueTitle: String {
        String(localized: "\(snippetsStore.issues.count) snippet files couldn’t be loaded")
    }

    private var snippetIssueMessage: String {
        let first = snippetsStore.issues[0]
        if snippetsStore.issues.count == 1 {
            return "\(first.fileURL.lastPathComponent): \(first.message)"
        }
        let remaining = snippetsStore.issues.count - 1
        return String(
            localized: "\(first.fileURL.lastPathComponent): \(first.message) Plus \(remaining) more.")
    }
}

private struct SnippetsLibraryBrowser: View {
    @Environment(SnippetCoordinator.self) private var coordinator
    @Environment(SnippetsStore.self) private var snippetsStore
    @Binding var selection: SnippetCollectionSelection
    @State private var filterText = ""
    @State private var dropTarget: SnippetCollectionSelection?

    private var knownFolderPaths: Set<String> {
        Set(snippetsStore.folders.map(\.path))
    }

    private var orderedFolders: [SnippetFolder] {
        var result: [SnippetFolder] = []
        func appendChildren(of parent: String?) {
            let children = snippetsStore.childFolders(in: parent, includeDisabled: true)
            for child in children {
                result.append(child)
                appendChildren(of: child.path)
            }
        }
        appendChildren(of: nil)
        return result
    }

    private var unfiledSnippets: [StoredSnippet] {
        snippetsStore.snippets
            .filter { record in
                guard let folder = record.snippet.folder else { return true }
                return !knownFolderPaths.contains(folder)
            }
            .sorted(by: nameOrder)
    }

    private var collectionSnippets: [StoredSnippet] {
        switch selection {
        case .all:
            return snippetsStore.snippets.sorted(by: nameOrder)
        case .root:
            return unfiledSnippets
        case .folder(let path):
            return snippetsStore.directSnippets(in: path, includeDisabled: true).sorted(by: nameOrder)
        }
    }

    private var displayedSnippets: [StoredSnippet] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return collectionSnippets }
        return collectionSnippets.filter { record in
            let keyword = snippetsStore.effectiveKeyword(for: record) ?? record.snippet.keyword ?? ""
            let folder = record.snippet.folder ?? ""
            return record.snippet.name.localizedCaseInsensitiveContains(query)
                || keyword.localizedCaseInsensitiveContains(query)
                || record.fileURL.lastPathComponent.localizedCaseInsensitiveContains(query)
                || folder.localizedCaseInsensitiveContains(query)
        }
    }

    private func nameOrder(_ lhs: StoredSnippet, _ rhs: StoredSnippet) -> Bool {
        lhs.snippet.name.localizedCaseInsensitiveCompare(rhs.snippet.name) == .orderedAscending
    }

    var body: some View {
        HStack(spacing: 0) {
            collectionsPane
                .frame(width: 220)

            Divider()

            snippetsPane
                .frame(maxWidth: .infinity)
        }
        .frame(height: 430)
        .onChange(of: snippetsStore.folders) { _, _ in
            guard case .folder(let path) = selection, snippetsStore.folder(at: path) == nil else {
                return
            }
            if let parent = SnippetFolderPath.parent(of: path), snippetsStore.folder(at: parent) != nil {
                selection = .folder(parent)
            } else {
                selection = .all
            }
        }
    }

    private var collectionsPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Collections"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 34)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    SnippetCollectionRow(
                        title: String(localized: "All Snippets"),
                        icon: nil,
                        systemIcon: "tray.full",
                        count: snippetsStore.snippets.count,
                        prefix: "",
                        indentLevel: 0,
                        isEnabled: true,
                        isSelected: selection == .all,
                        isDropTargeted: false
                    ) {
                        selection = .all
                    }

                    SnippetCollectionRow(
                        title: String(localized: "Unfiled"),
                        icon: nil,
                        systemIcon: "doc.text",
                        count: unfiledSnippets.count,
                        prefix: "",
                        indentLevel: 0,
                        isEnabled: true,
                        isSelected: selection == .root,
                        isDropTargeted: dropTarget == .root
                    ) {
                        selection = .root
                    }
                    .dropDestination(for: String.self) { items, _ in
                        handleDrop(items: items, toFolder: nil)
                    } isTargeted: { targeted in
                        dropTarget = targeted ? .root : (dropTarget == .root ? nil : dropTarget)
                    }

                    if !orderedFolders.isEmpty {
                        Divider()
                            .padding(.vertical, 4)

                        ForEach(orderedFolders) { folder in
                            let folderSel = SnippetCollectionSelection.folder(folder.path)
                            let effectiveEnabled = snippetsStore.isFolderEffectivelyEnabled(folder.path)
                            let effectivePrefix = snippetsStore.effectivePrefix(for: folder.path)
                            let count = snippetsStore.snippetCount(in: folder.path, includeDisabled: true)

                            SnippetCollectionRow(
                                title: folder.name,
                                icon: folder.icon,
                                systemIcon: nil,
                                count: count,
                                prefix: effectivePrefix,
                                indentLevel: max(0, folder.depth - 1),
                                isEnabled: effectiveEnabled,
                                isSelected: selection == folderSel,
                                isDropTargeted: dropTarget == folderSel
                            ) {
                                selection = folderSel
                            }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    selection = folderSel
                                    coordinator.configureFolder(at: folder.path)
                                }
                            )
                            .dropDestination(for: String.self) { items, _ in
                                handleDrop(items: items, toFolder: folder.path)
                            } isTargeted: { targeted in
                                dropTarget = targeted ? folderSel : (dropTarget == folderSel ? nil : dropTarget)
                            }
                            .contextMenu {
                                folderContextMenu(for: folder)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.xs)
            }

            Divider()

            collectionsToolbar
        }
    }

    private var collectionsToolbar: some View {
        let selectedFolder = selection.folderPath.flatMap(snippetsStore.folder(at:))
        return HStack(spacing: Theme.Spacing.sm) {
            if let folder = selectedFolder, folder.depth < SnippetFolderPath.maxDepth {
                Menu {
                    Button(String(localized: "New Top-Level Folder…")) {
                        Task {
                            if let created = await coordinator.createFolder(parentPath: nil) {
                                selection = .folder(created.path)
                            }
                        }
                    }
                    Button(String(localized: "New Subfolder in “\(folder.name)”…")) {
                        Task {
                            if let created = await coordinator.createFolder(parentPath: folder.path) {
                                selection = .folder(created.path)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("New Folder")
            } else {
                Button {
                    Task {
                        if let created = await coordinator.createFolder(parentPath: nil) {
                            selection = .folder(created.path)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Folder")
            }

            Button {
                if let path = selection.folderPath {
                    Task { await coordinator.deleteFolder(at: path) }
                }
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .disabled(selectedFolder == nil)
            .help("Delete Selected Folder")

            Button {
                if let path = selection.folderPath {
                    coordinator.configureFolder(at: path)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .disabled(selectedFolder == nil)
            .help("Configure Folder")

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 30)
    }

    private var snippetsPane: some View {
        VStack(spacing: 0) {
            snippetsTopBar

            Divider()

            if displayedSnippets.isEmpty {
                snippetsEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedSnippets) { record in
                            SnippetBrowserItemRow(
                                record: record,
                                effectiveKeyword: snippetsStore.effectiveKeyword(for: record),
                                showsFolderBadge: selection == .all,
                                folders: orderedFolders,
                                onEdit: { coordinator.editSnippet(record) },
                                onDuplicate: { coordinator.duplicateSnippet(record) },
                                onSetEnabled: { enabled in
                                    Task { await coordinator.setSnippetEnabled(enabled, id: record.id) }
                                },
                                onMove: { targetFolder in
                                    Task { await coordinator.moveSnippet(id: record.id, toFolder: targetFolder) }
                                },
                                onReveal: { coordinator.showSnippetInFinder(record) },
                                onDelete: { Task { await coordinator.deleteSnippet(id: record.id) } }
                            )
                            Divider()
                                .padding(.leading, Theme.Spacing.md)
                        }
                    }
                }
            }

            Divider()

            snippetsFooterBar
        }
    }

    private var snippetsTopBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Filter collection…"), text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            )

            Button {
                coordinator.editSnippet(nil, initialFolder: selection.folderPath)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("New Snippet")
            .accessibilityLabel("New Snippet")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 34)
    }

    private var snippetsEmptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Spacer()
            Image(systemName: filterText.isEmpty ? "curlybraces" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(
                filterText.isEmpty
                    ? String(localized: "No snippets in this collection.")
                    : String(localized: "No matching snippets.")
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            if filterText.isEmpty {
                Button(String(localized: "New Snippet")) {
                    coordinator.editSnippet(nil, initialFolder: selection.folderPath)
                }
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var snippetsFooterBar: some View {
        let selectedFolder = selection.folderPath.flatMap(snippetsStore.folder(at:))
        return HStack(spacing: Theme.Spacing.md) {
            Text(String(localized: "\(displayedSnippets.count) snippets"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if let folder = selectedFolder {
                let prefix = snippetsStore.effectivePrefix(for: folder.path)
                if !prefix.isEmpty {
                    Text(verbatim: prefix)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.Colors.controlSurface)
                        )
                }

                Toggle(
                    String(localized: "Enabled"),
                    isOn: Binding(
                        get: { folder.isEnabled },
                        set: { enabled in
                            Task { await coordinator.setFolderEnabled(enabled, at: folder.path) }
                        })
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 30)
    }

    @ViewBuilder
    private func folderContextMenu(for folder: SnippetFolder) -> some View {
        Button(String(localized: "New Snippet in Folder…")) {
            coordinator.editSnippet(nil, initialFolder: folder.path)
        }
        if folder.depth < SnippetFolderPath.maxDepth {
            Button(String(localized: "New Subfolder…")) {
                Task {
                    if let created = await coordinator.createFolder(parentPath: folder.path) {
                        selection = .folder(created.path)
                    }
                }
            }
        }
        Divider()
        Button(String(localized: "Configure Folder…")) {
            coordinator.configureFolder(at: folder.path)
        }
        Button(folder.isEnabled ? String(localized: "Disable Folder") : String(localized: "Enable Folder")) {
            Task { await coordinator.setFolderEnabled(!folder.isEnabled, at: folder.path) }
        }
        Button(String(localized: "Show in Finder")) {
            coordinator.showFolderInFinder(at: folder.path)
        }
        Divider()
        Button(String(localized: "Delete Folder…"), role: .destructive) {
            Task { await coordinator.deleteFolder(at: folder.path) }
        }
    }

    private func handleDrop(items: [String], toFolder folderPath: String?) -> Bool {
        let validIDs = items.filter { snippetsStore.record(id: $0) != nil }
        guard !validIDs.isEmpty else { return false }
        Task {
            for id in validIDs {
                await coordinator.moveSnippet(id: id, toFolder: folderPath)
            }
        }
        return true
    }
}

private struct SnippetCollectionRow: View {
    let title: String
    let icon: String?
    let systemIcon: String?
    let count: Int
    let prefix: String
    let indentLevel: Int
    let isEnabled: Bool
    let isSelected: Bool
    let isDropTargeted: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color.white : .secondary)
                        .frame(width: 16, height: 16)
                } else {
                    SnippetFolderIconView(icon: icon, size: 15)
                }

                Text(verbatim: title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(
                        isSelected ? Color.white : (isEnabled ? Color.primary : Color.secondary)
                    )

                Spacer(minLength: 4)

                if !prefix.isEmpty {
                    Text(verbatim: prefix)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }

                Text(verbatim: "\(count)")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
            }
            .padding(.leading, CGFloat(8 + indentLevel * 12))
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isDropTargeted ? Theme.Colors.settingsAccent : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled || isSelected ? 1.0 : 0.65)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Theme.Colors.settingsAccent
        }
        if isDropTargeted {
            return Theme.Colors.settingsAccent.opacity(0.14)
        }
        return Color.clear
    }
}

private struct SnippetBrowserItemRow: View {
    let record: StoredSnippet
    let effectiveKeyword: String?
    let showsFolderBadge: Bool
    let folders: [SnippetFolder]
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onSetEnabled: (Bool) -> Void
    let onMove: (String?) -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            EntryIconView(source: SnippetFaviconService.resolveIcon(for: record.snippet))
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
                .opacity(record.snippet.isEnabled ? 1.0 : 0.5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: record.snippet.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if showsFolderBadge, let folder = record.snippet.folder {
                        Text(verbatim: folder)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Theme.Colors.controlSurface)
                            )
                            .lineLimit(1)
                    }
                }

                Text(verbatim: metadataSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .opacity(record.snippet.isEnabled ? 1.0 : 0.55)

            Spacer(minLength: Theme.Spacing.sm)

            ShortcutRecorder(action: .snippet(id: record.id))
                .settingsEnabled(record.snippet.isEnabled)

            Menu {
                moveMenuItems
            } label: {
                Image(systemName: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Move to Folder")
            .accessibilityLabel("Move \(record.snippet.name)")

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Snippet")
            .accessibilityLabel("Edit \(record.snippet.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Snippet")
            .accessibilityLabel("Delete \(record.snippet.name)")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .draggable(record.id)
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button(String(localized: "Edit Snippet…"), action: onEdit)
            Button(String(localized: "Duplicate Snippet…"), action: onDuplicate)
            Button(
                record.snippet.isEnabled
                    ? String(localized: "Disable Snippet")
                    : String(localized: "Enable Snippet")
            ) {
                onSetEnabled(!record.snippet.isEnabled)
            }
            Menu(String(localized: "Move to Folder")) {
                moveMenuItems
            }
            Button(String(localized: "Show in Finder"), action: onReveal)
            Divider()
            Button(String(localized: "Delete Snippet…"), role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var moveMenuItems: some View {
        Button {
            onMove(nil)
        } label: {
            if record.snippet.folder == nil {
                Label(String(localized: "Unfiled (Root)"), systemImage: "checkmark")
            } else {
                Text(String(localized: "Unfiled (Root)"))
            }
        }
        if !folders.isEmpty {
            Divider()
            ForEach(folders) { folder in
                let label = folder.path.split(separator: "/").joined(separator: " / ")
                Button {
                    onMove(folder.path)
                } label: {
                    if record.snippet.folder == folder.path {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(verbatim: label)
                    }
                }
            }
        }
    }

    private var metadataSubtitle: String {
        let filename = record.fileURL.lastPathComponent
        var parts: [String] = []
        if let keyword = effectiveKeyword ?? record.snippet.keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
           !keyword.isEmpty
        {
            parts.append(keyword)
        }
        parts.append(filename)
        if !record.snippet.isEnabled {
            parts.append(String(localized: "Disabled"))
        }
        return parts.joined(separator: " · ")
    }
}
