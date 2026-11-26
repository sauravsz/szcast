import SwiftUI

struct SnippetsScreen: PaletteScreen {
    let store: SnippetsStore
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    let openActions: () -> Void
    let actsWithoutRows = true

    var rows: [SnippetBrowserRow] {
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return store.browserRows(matching: query, in: vm.snippetFolderPath).map { .snippet($0) }
        }
        let currentFolder = vm.snippetFolderPath
        let folders = store.childFolders(in: currentFolder, includeDisabled: false).map { folder in
            SnippetBrowserRow.folder(
                folder,
                snippetCount: store.snippetCount(in: folder.path, includeDisabled: false),
                subfolderCount: store.subfolderCount(in: folder.path, includeDisabled: false))
        }
        let direct = store.directSnippets(in: currentFolder, includeDisabled: false)
        let orderedSnippets: [StoredSnippet]
        if currentFolder == nil {
            orderedSnippets = direct
        } else {
            orderedSnippets = direct.filter(\.snippet.isPinned) + direct.filter { !$0.snippet.isPinned }
        }
        return folders + orderedSnippets.map { .snippet($0) }
    }

    private var clampedSelection: Int {
        let count = rows.count
        return count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    var primaryActionTitle: String {
        if case .folder = row(at: clampedSelection) {
            return String(localized: "Open Folder")
        }
        switch core.settings.snippetsDefaultAction {
        case .paste: return String(localized: "Paste Snippet")
        case .copy: return String(localized: "Copy Snippet")
        case .copyAndPaste: return String(localized: "Copy & Paste Snippet")
        }
    }

    private func row(at selection: Int) -> SnippetBrowserRow? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .folder(let folder, _, _):
            return SnippetFolderActionsMenu.content(folder: folder, core: core)
        case .snippet(let record):
            return SnippetActionsMenu.content(
                record: record, currentFolder: vm.snippetFolderPath, core: core)
        case nil:
            return SnippetEmptyActionsMenu.content(currentFolder: vm.snippetFolderPath, core: core)
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        case .folder(let folder, _, _):
            vm.snippetFolderPath = folder.path
            vm.query = ""
        case .snippet(let record):
            core.snippetCoordinator.expandSnippetFromPalette(id: record.id)
        case nil:
            break
        }
    }

    func secondary(at selection: Int) -> Bool {
        guard case .snippet(let record) = row(at: selection) else { return false }
        core.snippetCoordinator.performFromPalette(
            core.settings.snippetsDefaultAction.alternate, id: record.id)
        return true
    }

    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        guard axis == .horizontal, vm.query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        if delta > 0, case .folder(let folder, _, _) = row(at: selection) {
            vm.snippetFolderPath = folder.path
            return 0
        }
        if delta < 0, vm.popSnippetFolder() {
            return 0
        }
        return nil
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .newItem {
            core.snippetCoordinator.editSnippet(nil, initialFolder: vm.snippetFolderPath)
            return true
        }
        switch row(at: selection) {
        case .folder(let folder, _, _):
            switch shortcut {
            case .edit:
                core.snippetCoordinator.configureFolder(at: folder.path)
            case .showInFinder:
                core.snippetCoordinator.showFolderInFinder(at: folder.path)
            case .delete:
                Task { await core.snippetCoordinator.deleteFolder(at: folder.path) }
            default:
                return false
            }
            return true
        case .snippet(let record):
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
            default:
                return false
            }
            return true
        case nil:
            return false
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        if rows.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            let selected = rows.indices.contains(selection) ? rows[selection] : nil
            HStack(spacing: 0) {
                SnippetsList(
                    results: rows,
                    showFolderLabel: !query.isEmpty,
                    showPinnedHeader: vm.snippetFolderPath != nil || !query.isEmpty,
                    effectiveKeyword: { store.effectiveKeyword(for: $0) },
                    selectedID: selected?.id,
                    scroll: scroll,
                    onSelect: { item in
                        vm.selection = rows.firstIndex(of: item) ?? 0
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { item in
                        if let index = rows.firstIndex(of: item) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                SnippetPreview(row: selected, store: store)
            }
        }
    }

    /// An empty library and an over-narrow filter are different problems with different answers.
    private var emptyMessage: String {
        if store.state == .loading { return String(localized: "Loading snippets…") }
        if !vm.query.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "No matching snippets")
        }
        if vm.snippetFolderPath != nil {
            return String(localized: "Folder is empty")
        }
        return store.snippets.contains(where: { store.isSnippetEffectivelyEnabled($0) })
            ? String(localized: "No matching snippets") : String(localized: "No snippets yet")
    }
}

@MainActor
private enum SnippetEmptyActionsMenu {
    static func content(currentFolder: String?, core: AppCore) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: String(localized: "Create Snippet"), systemImage: "plus", shortcut: "⌘N"
            ) {
                core.snippetCoordinator.editSnippet(nil, initialFolder: currentFolder)
            }
        ]
        if (currentFolder.map(SnippetFolderPath.depth) ?? 0) < SnippetFolderPath.maxDepth {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "New Folder…"), systemImage: "folder.badge.plus"
                ) {
                    Task { await core.snippetCoordinator.createFolder(parentPath: currentFolder) }
                })
        }
        return PopoverMenuContent(
            header: currentFolder ?? String(localized: "Snippets"),
            items: items)
    }
}

@MainActor
private enum SnippetFolderActionsMenu {
    static func content(folder: SnippetFolder, core: AppCore) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: String(localized: "Open Folder"), systemImage: "folder", shortcut: "↵"
            ) {
                core.palette.snippetFolderPath = folder.path
                core.palette.query = ""
            },
            PopoverMenuItem(
                title: String(localized: "Create Snippet in Folder"), systemImage: "plus",
                startsSection: true, shortcut: "⌘N"
            ) {
                core.snippetCoordinator.editSnippet(nil, initialFolder: folder.path)
            }
        ]
        if folder.depth < SnippetFolderPath.maxDepth {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "New Subfolder…"), systemImage: "folder.badge.plus"
                ) {
                    Task { await core.snippetCoordinator.createFolder(parentPath: folder.path) }
                })
        }
        items.append(contentsOf: [
            PopoverMenuItem(
                title: String(localized: "Configure Folder…"), systemImage: "slider.horizontal.3",
                startsSection: true, shortcut: "⌘E"
            ) {
                core.snippetCoordinator.configureFolder(at: folder.path)
            },
            PopoverMenuItem(
                title: String(localized: "Disable Folder"), systemImage: "eye.slash"
            ) {
                Task { await core.snippetCoordinator.setFolderEnabled(false, at: folder.path) }
            },
            PopoverMenuItem(
                title: String(localized: "Show in Finder"), systemImage: "folder",
                startsSection: true, shortcut: "⌘F"
            ) {
                core.snippetCoordinator.showFolderInFinder(at: folder.path)
            },
            PopoverMenuItem(
                title: String(localized: "Delete Folder"), systemImage: "trash",
                startsSection: true, shortcut: "⌃X", isDestructive: true
            ) {
                Task { await core.snippetCoordinator.deleteFolder(at: folder.path) }
            }
        ])
        return PopoverMenuContent(header: folder.name, items: items)
    }
}

@MainActor
enum SnippetActionsMenu {
    static func content(
        record: StoredSnippet,
        currentFolder: String? = nil,
        core: AppCore
    ) -> PopoverMenuContent {
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
                title: String(localized: "Move to Folder…"), systemImage: "folder.badge.gearshape"
            ) {
                Task { await core.snippetCoordinator.moveSnippetToFolderPrompt(record) }
            },
            PopoverMenuItem(
                title: String(localized: "Create Snippet"), systemImage: "plus", shortcut: "⌘N"
            ) {
                core.snippetCoordinator.editSnippet(nil, initialFolder: currentFolder ?? record.snippet.folder)
            }
        ])

        if (currentFolder.map(SnippetFolderPath.depth) ?? 0) < SnippetFolderPath.maxDepth {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "New Folder…"), systemImage: "folder.badge.plus"
                ) {
                    Task { await core.snippetCoordinator.createFolder(parentPath: currentFolder) }
                })
        }

        items.append(contentsOf: [
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
