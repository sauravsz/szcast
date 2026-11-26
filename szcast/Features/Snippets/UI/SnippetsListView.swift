import SwiftUI

enum SnippetBrowserRow: Identifiable, Hashable {
    case folder(SnippetFolder, snippetCount: Int, subfolderCount: Int)
    case snippet(StoredSnippet)

    var id: String {
        switch self {
        case .folder(let folder, _, _): return "folder:" + folder.path
        case .snippet(let record): return "snippet:" + record.id
        }
    }
}

struct SnippetsList: View {
    @Environment(\.metrics) private var metrics
    let results: [SnippetBrowserRow]
    let showFolderLabel: Bool
    let showPinnedHeader: Bool
    let effectiveKeyword: (StoredSnippet) -> String?
    let selectedID: SnippetBrowserRow.ID?
    let scroll: ScrollIntent
    let onSelect: (SnippetBrowserRow) -> Void
    let onActivate: () -> Void
    let onActions: (SnippetBrowserRow) -> Void

    private enum DisplayRow: Identifiable {
        case header(String)
        case item(SnippetBrowserRow)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .item(let row): return row.id
            }
        }
    }

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    private var rows: [DisplayRow] {
        var displayRows: [DisplayRow] = []
        var currentTitle: String?
        for item in results {
            let title: String
            switch item {
            case .folder:
                title = String(localized: "Folders")
            case .snippet(let record):
                if showPinnedHeader && record.snippet.isPinned {
                    title = String(localized: "Pinned")
                } else {
                    title = String(localized: "Snippets")
                }
            }
            if title != currentTitle {
                displayRows.append(.header(title))
                currentTitle = title
            }
            displayRows.append(.item(item))
        }
        return displayRows
    }

    var body: some View {
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .item(let item):
                            rowView(for: item, selected: item.id == selectedID)
                                .selectionFrame(item.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(item) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelect(item)
                                        onActivate()
                                    }
                                )
                                .onRightClick { onActions(item) }
                        }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }

    @ViewBuilder
    private func rowView(for item: SnippetBrowserRow, selected: Bool) -> some View {
        switch item {
        case .folder(let folder, let snippetCount, let subfolderCount):
            SnippetFolderRow(
                folder: folder,
                snippetCount: snippetCount,
                subfolderCount: subfolderCount,
                selected: selected
            )
        case .snippet(let record):
            SnippetRow(
                record: record,
                showFolderLabel: showFolderLabel,
                effectiveKeyword: effectiveKeyword(record),
                selected: selected
            )
        }
    }
}

private struct SnippetFolderRow: View {
    @Environment(\.metrics) private var metrics
    let folder: SnippetFolder
    let snippetCount: Int
    let subfolderCount: Int
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var countLabel: String {
        if snippetCount == 0 && subfolderCount > 0 {
            return "\(subfolderCount)"
        }
        return "\(snippetCount)"
    }

    var body: some View {
        IconCache.observeStyle()
        return HStack(spacing: metrics.spacing.lg) {
            SnippetFolderIconView(icon: folder.icon, size: metrics.size.resultRowIcon)
            Text(folder.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.lg)
            if let prefix = folder.keywordPrefix, !prefix.isEmpty {
                Text(prefix)
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Text(countLabel)
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }
}

private struct SnippetRow: View {
    @Environment(\.metrics) private var metrics
    @Environment(HotKeyManager.self) private var hotKeys
    let record: StoredSnippet
    let showFolderLabel: Bool
    let effectiveKeyword: String?
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        IconCache.observeStyle()
        return HStack(spacing: metrics.spacing.lg) {
            EntryIconView(source: SnippetFaviconService.resolveIcon(for: record.snippet))
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(record.snippet.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            let excerpt = SnippetSearch.excerpt(for: record.snippet.text)
            if !excerpt.isEmpty {
                Text(excerpt)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: metrics.spacing.lg)
            if showFolderLabel, let folder = record.snippet.folder, !folder.isEmpty {
                HStack(spacing: metrics.spacing.xxs) {
                    Image(systemName: "folder")
                    Text(folder.split(separator: "/").joined(separator: " / "))
                }
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.head)
            }
            if let keyword = effectiveKeyword ?? record.snippet.keyword, !keyword.isEmpty {
                Text(keyword)
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            if let keycaps = hotKeys.binding(for: .snippet(id: record.id))?.keycaps {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(keycaps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }
}

struct SnippetPreview: View {
    let row: SnippetBrowserRow?
    let store: SnippetsStore

    var body: some View {
        switch row {
        case .snippet(let record):
            VStack(alignment: .leading, spacing: 0) {
                // The raw template: expanding here would read the clipboard on every arrow key.
                ScrollView {
                    Text(record.snippet.text)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                SnippetInfoSection(record: record, effectiveKeyword: store.effectiveKeyword(for: record))
            }
            .padding(.horizontal, 12)
        case .folder(let folder, let snippetCount, let subfolderCount):
            SnippetFolderPreview(
                folder: folder,
                snippetCount: snippetCount,
                subfolderCount: subfolderCount,
                store: store
            )
            .padding(.horizontal, 12)
        case nil:
            Color.clear
        }
    }
}

private struct SnippetFolderPreview: View {
    @Environment(\.metrics) private var metrics
    let folder: SnippetFolder
    let snippetCount: Int
    let subfolderCount: Int
    let store: SnippetsStore

    private var directSnippets: [StoredSnippet] {
        store.directSnippets(in: folder.path, includeDisabled: false)
    }

    private var childFolders: [SnippetFolder] {
        store.childFolders(in: folder.path, includeDisabled: false)
    }

    private var effectivePrefix: String {
        store.effectivePrefix(for: folder.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.spacing.md) {
                    HStack(spacing: metrics.spacing.md) {
                        SnippetFolderIconView(icon: folder.icon, size: 28)
                        VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                            Text(folder.name)
                                .font(metrics.typography.panelTitle)
                            Text(folder.path.split(separator: "/").joined(separator: " / "))
                                .font(metrics.typography.keyCap)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .padding(.top, metrics.spacing.xs)

                    if childFolders.isEmpty && directSnippets.isEmpty {
                        Text("Empty folder. Press ↵ to open or ⌘N to add a snippet.")
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .padding(.top, metrics.spacing.sm)
                    } else {
                        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                            ForEach(childFolders.prefix(6)) { child in
                                HStack(spacing: metrics.spacing.sm) {
                                    SnippetFolderIconView(icon: child.icon, size: 16)
                                    Text(child.name)
                                        .font(metrics.typography.rowTitle)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(store.snippetCount(in: child.path))")
                                        .font(metrics.typography.keyCap)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                            ForEach(directSnippets.prefix(12)) { record in
                                HStack(spacing: metrics.spacing.sm) {
                                    EntryIconView(source: SnippetFaviconService.resolveIcon(for: record.snippet))
                                        .frame(width: 16, height: 16)
                                    Text(record.snippet.name)
                                        .font(metrics.typography.rowTitle)
                                        .lineLimit(1)
                                    Spacer()
                                    if let kw = store.effectiveKeyword(for: record) {
                                        Text(kw)
                                            .font(metrics.typography.keyCap)
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            SnippetFolderInfoSection(
                folder: folder,
                snippetCount: snippetCount,
                subfolderCount: subfolderCount,
                effectivePrefix: effectivePrefix
            )
        }
    }
}

private struct SnippetFolderInfoSection: View {
    @Environment(\.metrics) private var metrics
    let folder: SnippetFolder
    let snippetCount: Int
    let subfolderCount: Int
    let effectivePrefix: String

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var rows: [InfoRow] {
        var rows = [
            InfoRow(
                label: String(localized: "Folder"),
                value: folder.path.split(separator: "/").joined(separator: " / ")),
            InfoRow(label: String(localized: "Snippets"), value: snippetCount.formatted())
        ]
        if subfolderCount > 0 {
            rows.append(
                InfoRow(label: String(localized: "Subfolders"), value: subfolderCount.formatted()))
        }
        if !effectivePrefix.isEmpty {
            rows.append(InfoRow(label: String(localized: "Keyword Prefix"), value: effectivePrefix))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Information")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
    }
}

/// The "Information" block; everything in it is already in memory, so nothing is gathered off-main.
private struct SnippetInfoSection: View {
    @Environment(\.metrics) private var metrics
    @Environment(HotKeyManager.self) private var hotKeys
    let record: StoredSnippet
    let effectiveKeyword: String?

    private struct InfoRow: Identifiable {
        let label: String
        let value: Text
        var id: String { label }

        init(label: String, value: String) {
            self.label = label
            self.value = Text(value)
        }

        init(label: String, keycaps: [String]) {
            self.label = label
            value = KeyCapChip.inlineText(keycaps)
        }
    }

    private var rows: [InfoRow] {
        var rows = [InfoRow(label: String(localized: "Name"), value: record.snippet.name)]
        if let folder = record.snippet.folder, !folder.isEmpty {
            rows.append(
                InfoRow(
                    label: String(localized: "Folder"),
                    value: folder.split(separator: "/").joined(separator: " / ")))
        }
        if let effectiveKeyword, !effectiveKeyword.isEmpty {
            rows.append(InfoRow(label: String(localized: "Keyword"), value: effectiveKeyword))
        }
        if let keycaps = hotKeys.binding(for: .snippet(id: record.id))?.keycaps {
            rows.append(InfoRow(label: String(localized: "Shortcut"), keycaps: keycaps))
        }
        rows.append(
            InfoRow(label: String(localized: "File"), value: record.fileURL.lastPathComponent))
        rows.append(
            InfoRow(
                label: String(localized: "Characters"),
                value: record.snippet.text.count.formatted()))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Information")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        row.value.lineLimit(1).truncationMode(.middle)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
    }
}
