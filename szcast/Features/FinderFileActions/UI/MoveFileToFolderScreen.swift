import AppKit
import SwiftUI

struct MoveFileToFolderScreen: PaletteScreen {
    let service: FinderFileActionsService
    let core: AppCore
    let vm: PaletteState

    @State private var selectedItems: [URL] = []
    @State private var hasScannedSelection = false

    struct Row: Identifiable {
        let id: String
        let destination: FinderFolderDestination?
        let isNoSelection: Bool
        let title: String
        let subtitle: String?
        let tag: String?
    }

    private func currentSelection() -> [URL] {
        if hasScannedSelection {
            return selectedItems
        }
        return service.getSelectedItems()
    }

    private var selectionSummary: String {
        let items = currentSelection()
        guard !items.isEmpty else { return "" }
        if items.count == 1 {
            return items[0].lastPathComponent
        } else {
            let names = items.prefix(2).map(\.lastPathComponent).joined(separator: ", ")
            let remaining = items.count > 2 ? " +\(items.count - 2) more" : ""
            return "\(items.count) items (\(names)\(remaining))"
        }
    }

    var rows: [Row] {
        let items = currentSelection()
        if items.isEmpty {
            return [
                Row(
                    id: "no-selection",
                    destination: nil,
                    isNoSelection: true,
                    title: String(localized: "No files selected in Finder"),
                    subtitle: String(localized: "Select one or more files in Finder, then press Hyper+M to move them."),
                    tag: nil
                )
            ]
        }

        let query = vm.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var destinations: [FinderFolderDestination] = []
        var seenPaths = Set<String>()

        // 1. Pinned folders
        for folder in service.pinnedFolders {
            let path = folder.standardizedFileURL.path
            guard !seenPaths.contains(path) else { continue }
            let name = folder.lastPathComponent.lowercased()
            if query.isEmpty || name.contains(query) || path.lowercased().contains(query) {
                seenPaths.insert(path)
                destinations.append(FinderFolderDestination(url: folder, kind: .pinned))
            }
        }

        // 2. Recent folders
        for folder in service.recentFolders {
            let path = folder.standardizedFileURL.path
            guard !seenPaths.contains(path) else { continue }
            let name = folder.lastPathComponent.lowercased()
            if query.isEmpty || name.contains(query) || path.lowercased().contains(query) {
                seenPaths.insert(path)
                destinations.append(FinderFolderDestination(url: folder, kind: .recent))
            }
        }

        // 3. Spotlight folders when typing query
        if !query.isEmpty {
            let spotlight = service.searchSpotlightFolders(query: query, limit: 20)
            for folder in spotlight {
                let path = folder.standardizedFileURL.path
                guard !seenPaths.contains(path) else { continue }
                seenPaths.insert(path)
                destinations.append(FinderFolderDestination(url: folder, kind: .search))
            }
        }

        return destinations.map { dest in
            Row(
                id: dest.id,
                destination: dest,
                isNoSelection: false,
                title: dest.name,
                subtitle: dest.displayPath,
                tag: dest.kind == .pinned ? "Pinned" : (dest.kind == .recent ? "Recent" : nil)
            )
        }
    }

    var primaryActionTitle: String {
        let items = currentSelection()
        if items.isEmpty {
            return ""
        }
        return String(localized: "Move to Folder")
    }

    func activate(at selection: Int) {
        let list = rows
        guard list.indices.contains(selection) else { return }
        let row = list[selection]

        if row.isNoSelection { return }

        guard let dest = row.destination else { return }
        let items = currentSelection()
        guard !items.isEmpty else { return }

        do {
            let result = try service.moveItems(sources: items, to: dest.url)
            core.paletteCoordinator.hidePalette()
            core.showMessage(result.message, tone: .success)
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
        }
    }

    func secondary(at selection: Int) -> Bool {
        let list = rows
        guard list.indices.contains(selection) else { return false }
        let row = list[selection]
        if row.isNoSelection { return false }

        guard let dest = row.destination else { return false }
        let items = currentSelection()
        guard !items.isEmpty else { return false }

        do {
            let result = try service.copyItems(sources: items, to: dest.url)
            core.paletteCoordinator.hidePalette()
            core.showMessage(result.message, tone: .success)
            return true
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
            return false
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let items = rows

        return AnyView(
            VStack(spacing: 0) {
                // Header badge if files are selected
                let summary = selectionSummary
                if !summary.isEmpty {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "arrow.right.doc.on.clipboard")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(String(localized: "Moving: \(summary)"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.cardFill)
                }

                if items.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "No matching destination folders found"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Try searching a different folder name or path."))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Theme.Spacing.xxl)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                                HStack(spacing: Theme.Spacing.md) {
                                    // Folder Icon
                                    Image(systemName: row.isNoSelection ? "xmark.circle" : (row.tag == "Pinned" ? "pin.fill" : "folder.fill"))
                                        .font(.system(size: 15))
                                        .foregroundStyle(row.isNoSelection ? .secondary : Color.accentColor)
                                        .frame(width: 24, height: 24)

                                    // Folder Name and Path
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        if let sub = row.subtitle {
                                            Text(sub)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    // Tag badge
                                    if let tag = row.tag {
                                        Text(tag)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(Color.accentColor)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(index == selection ? Theme.Colors.selection : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    activate(at: index)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
            .onAppear {
                selectedItems = service.getSelectedItems()
                hasScannedSelection = true
            }
        )
    }
}
