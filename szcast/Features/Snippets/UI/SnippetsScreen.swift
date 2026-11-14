import SwiftUI

struct SnippetsScreen: PaletteScreen {
    let store: SnippetsStore
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    let openActions: () -> Void

    /// A disabled snippet is off everywhere, so the browser lists exactly what the launcher does.
    var availableFolders: [String] {
        let folders = Set(
            store.snippets.compactMap {
                $0.snippet.folder?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty })
        return folders.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var folderCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for record in store.snippets where record.snippet.isEnabled {
            if let folder = record.snippet.folder?.trimmingCharacters(in: .whitespacesAndNewlines), !folder.isEmpty {
                counts[folder, default: 0] += 1
            }
        }
        return counts
    }

    var rows: [StoredSnippet] {
        let enabled = store.snippets.filter { $0.snippet.isEnabled }
        let filtered: [StoredSnippet]
        if let folder = vm.snippetFolderFilter, !folder.isEmpty {
            filtered = enabled.filter { $0.snippet.folder == folder }
        } else {
            filtered = enabled
        }
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        let matches: [StoredSnippet]
        if query.isEmpty {
            matches = filtered
        } else {
            matches = filtered.filter { record in
                record.snippet.name.localizedCaseInsensitiveContains(query)
                    || record.snippet.keyword?.localizedCaseInsensitiveContains(query) == true
                    || record.snippet.folder?.localizedCaseInsensitiveContains(query) == true
            }
        }
        return matches.filter(\.snippet.isPinned) + matches.filter { !$0.snippet.isPinned }
    }

    var primaryActionTitle: String {
        switch core.settings.snippetsDefaultAction {
        case .paste: return String(localized: "Paste Snippet")
        case .copy: return String(localized: "Copy Snippet")
        case .copyAndPaste: return String(localized: "Copy & Paste Snippet")
        }
    }

    private func record(at selection: Int) -> StoredSnippet? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let record = record(at: selection) else { return nil }
        return SnippetActionsMenu.content(record: record, core: core)
    }

    func activate(at selection: Int) {
        guard let record = record(at: selection) else { return }
        core.snippetCoordinator.expandSnippetFromPalette(id: record.id)
    }

    func secondary(at selection: Int) -> Bool {
        guard let record = record(at: selection) else { return false }
        core.snippetCoordinator.performFromPalette(core.settings.snippetsDefaultAction.alternate, id: record.id)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .newItem {
            core.snippetCoordinator.editSnippet(nil)
            return true
        }
        guard let record = record(at: selection) else { return false }
        switch shortcut {
        case .duplicate:
            core.snippetCoordinator.duplicateSnippet(record)
        case .edit:
            core.snippetCoordinator.editSnippet(record)
        case .pin:
            Task { await core.snippetCoordinator.toggleSnippetPinned(id: record.id) }
        case .showInFinder:
            core.snippetCoordinator.showSnippetInFinder(record)
        case .delete:
            Task { await core.snippetCoordinator.deleteSnippet(id: record.id) }
        default: return false
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        let folders = availableFolders
        if rows.isEmpty && folders.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            let selected = record(at: selection)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if !folders.isEmpty {
                        SnippetFolderChips(
                            folders: folders,
                            counts: folderCounts,
                            totalCount: store.snippets.count { $0.snippet.isEnabled },
                            selectedFolder: vm.snippetFolderFilter,
                            onSelect: { folder in
                                vm.snippetFolderFilter = folder
                            }
                        )
                        Rectangle().fill(Theme.Colors.separator).frame(height: Theme.Size.hairline)
                    }
                    if rows.isEmpty {
                        EmptyResults(text: emptyMessage)
                            .frame(maxHeight: .infinity)
                    } else {
                        SnippetsList(
                            results: rows, selectedID: selected?.id, scroll: scroll,
                            onSelect: { record in
                                vm.selection = rows.firstIndex(of: record) ?? 0
                            },
                            onActivate: { activate(at: vm.selection) },
                            onActions: { record in
                                if let index = rows.firstIndex(of: record) { vm.selection = index }
                                openActions()
                            }
                        )
                    }
                }
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                SnippetPreview(record: selected)
            }
        }
    }

    /// An empty library and an over-narrow filter are different problems with different answers.
    private var emptyMessage: String {
        if store.state == .loading { return String(localized: "Loading snippets…") }
        return store.snippets.contains(where: { $0.snippet.isEnabled })
            ? String(localized: "No matching snippets") : String(localized: "No snippets yet")
    }
}

@MainActor
enum SnippetActionsMenu {
    static func content(record: StoredSnippet, core: AppCore) -> PopoverMenuContent {
        let defaultAction = core.settings.snippetsDefaultAction
        var items: [PopoverMenuItem] = []

        switch defaultAction {
        case .paste:
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Paste Snippet"), systemImage: "text.quote", shortcut: "↵"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id, action: .paste)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy to Clipboard"), systemImage: "doc.on.doc", shortcut: "⌘C"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id, action: .copy)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy and Paste"), systemImage: "doc.on.clipboard", shortcut: "⌥↵"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id, action: .copyAndPaste)
                })

        case .copy:
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy to Clipboard"), systemImage: "doc.on.doc", shortcut: "↵"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id, action: .copy)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Paste Snippet"), systemImage: "text.quote", shortcut: "⌘V"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id, action: .paste)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy and Paste"), systemImage: "doc.on.clipboard", shortcut: "⌥↵"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id, action: .copyAndPaste)
                })

        case .copyAndPaste:
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy and Paste"), systemImage: "doc.on.clipboard", shortcut: "↵"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id, action: .copyAndPaste)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Paste Snippet"), systemImage: "text.quote", shortcut: "⌘V"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id, action: .paste)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy to Clipboard"), systemImage: "doc.on.doc", shortcut: "⌘C"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id, action: .copy)
                })
        }

        items.append(contentsOf: [
            PopoverMenuItem(
                title: String(localized: "Edit Snippet"), systemImage: "pencil", startsSection: true,
                shortcut: "⌘E"
            ) {
                core.snippetCoordinator.editSnippet(record)
            },
            PopoverMenuItem(
                title: String(localized: "Duplicate Snippet"), systemImage: "plus.square.on.square",
                shortcut: "⌘D"
            ) {
                core.snippetCoordinator.duplicateSnippet(record)
            },
            PopoverMenuItem(
                title: String(localized: "Create Snippet"), systemImage: "plus", shortcut: "⌘N"
            ) {
                core.snippetCoordinator.editSnippet(nil)
            },
            PopoverMenuItem(
                title: record.snippet.isPinned ? String(localized: "Unpin Snippet") : String(localized: "Pin Snippet"),
                systemImage: record.snippet.isPinned ? "pin.slash" : "pin", shortcut: "⌘."
            ) {
                Task { await core.snippetCoordinator.toggleSnippetPinned(id: record.id) }
            },
            PopoverMenuItem(
                title: String(localized: "Show in Finder"), systemImage: "folder", startsSection: true,
                shortcut: "⌘F"
            ) {
                core.snippetCoordinator.showSnippetInFinder(record)
            },
            PopoverMenuItem(
                title: String(localized: "Delete Snippet"), systemImage: "trash", startsSection: true,
                shortcut: "⌃X", isDestructive: true
            ) {
                Task { await core.snippetCoordinator.deleteSnippet(id: record.id) }
            }
        ])

        return PopoverMenuContent(header: record.snippet.name, items: items)
    }
}

private struct SnippetFolderChips: View {
    @Environment(\.metrics) private var metrics
    let folders: [String]
    let counts: [String: Int]
    let totalCount: Int
    let selectedFolder: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: metrics.spacing.xs) {
                chip(title: String(localized: "All"), count: totalCount, isSelected: selectedFolder == nil) {
                    onSelect(nil)
                }
                ForEach(folders, id: \.self) { folder in
                    chip(title: folder, count: counts[folder] ?? 0, isSelected: selectedFolder == folder) {
                        onSelect(folder)
                    }
                }
            }
            .padding(.horizontal, metrics.spacing.md)
            .padding(.vertical, metrics.spacing.xs)
        }
    }

    private func chip(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: metrics.spacing.xs) {
                Text(title)
                Text("\(count)")
                    .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            }
            .font(metrics.typography.keyCap)
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.attachmentChip, style: .continuous)
                    .fill(isSelected ? Theme.Colors.selection : Theme.Colors.rowHover)
            )
            .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }
}
