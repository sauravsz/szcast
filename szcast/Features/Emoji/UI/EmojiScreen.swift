import SwiftUI

/// The emoji and symbol picker: a sectioned grid whose ↑/↓ move by visual row, not by index.
struct EmojiScreen: PaletteScreen {
    let index: EmojiIndex
    let frequent: FrequentEmojiStore
    let pinned: PinnedEmojiStore
    let core: AppCore
    let vm: PaletteState
    let tone: EmojiSkinTone
    let defaultColumns: EmojiGridColumns
    let openActions: () -> Void

    private var columns: EmojiGridColumns {
        vm.emojiGridColumnsOverride ?? defaultColumns
    }

    /// The pins the grid shows; a stored glyph the catalog lacks must not shift any position.
    private var visiblePins: [String] {
        pinned.glyphs.filter { index.entry(for: $0) != nil }
    }

    private var isBrowsing: Bool {
        vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Pinned is the first section here, so a pin's position is also its flat selection index.
    private var pinsLeadGrid: Bool {
        isBrowsing && (vm.emojiCategoryFilter == .all || vm.emojiCategoryFilter == .pinned)
    }

    private var sections: [EmojiGridSection] {
        EmojiGrid.sections(
            query: vm.query, index: index, frequent: frequent, pinned: pinned,
            filter: vm.emojiCategoryFilter, columns: columns,
            isShowingAI: vm.emojiShowingAIResults)
    }

    /// Flat grid order across sections — what the selection indexes.
    var rows: [EmojiEntry] { sections.flatMap(\.entries) }

    var primaryActionTitle: String {
        core.settings.emojiPrimaryAction == .paste
            ? (vm.pasteTarget?.pasteTitle ?? String(localized: "Paste"))
            : String(localized: "Copy to Clipboard")
    }

    private func entry(at selection: Int) -> EmojiEntry? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection) else { return nil }
        let pins = visiblePins
        return EmojiActionsMenu.content(
            entry: entry, core: core, target: vm.pasteTarget,
            pinPosition: pins.firstIndex(of: entry.glyph), pinCount: pins.count,
            query: vm.query,
            canZoom: { columns.applying($0, default: defaultColumns) != nil },
            togglePin: { togglePin(entry) },
            movePin: { movePin(entry, by: $0) },
            zoom: zoom)
    }

    func activate(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        if core.settings.emojiPrimaryAction == .paste {
            core.emojiCoordinator.pasteEmoji(entry, query: vm.query)
        } else {
            core.emojiCoordinator.copyEmoji(entry, query: vm.query)
        }
    }

    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        if core.settings.emojiPrimaryAction == .paste {
            core.emojiCoordinator.copyEmoji(entry, query: vm.query)
        } else {
            core.emojiCoordinator.pasteEmoji(entry, query: vm.query)
        }
        return true
    }

    /// ⌥↵ or ⇧⌘↵ — the palette stays up, so a run of emoji goes over without re-summoning it.
    func pasteKeepingWindowOpen(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        core.emojiCoordinator.pasteEmojiKeepingWindowOpen(entry, query: vm.query)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        switch shortcut {
        case .pin:
            togglePin(entry)
            return true
        case .edit:
            core.emojiCoordinator.editCustomKeywords(for: entry)
            return true
        default:
            return false
        }
    }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        guard !isBrowsing else { return false }
        vm.emojiShowingAIResults.toggle()
        return true
    }

    /// ⌥⌘↑/↓ on the selected cell, when it is pinned.
    func movePin(_ delta: Int, at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        movePin(entry, by: delta)
    }

    func zoom(_ zoom: EmojiGridZoom) {
        guard let next = columns.applying(zoom, default: defaultColumns) else { return }
        vm.emojiGridColumnsOverride = next == defaultColumns ? nil : next
    }

    /// Blind to the filter and query, so only a use or a density change rewrites it.
    var frequentlyUsed: [String] {
        EmojiGrid.frequentlyUsed(frequent, in: index, columns: columns).map(\.glyph)
    }

    func frequentlyUsedChanged(from old: [String], to new: [String]) {
        guard isBrowsing else { return }
        let start: Int
        switch vm.emojiCategoryFilter {
        case .all: start = visiblePins.count
        case .frequentlyUsed: start = 0
        case .pinned, .category: return
        }
        vm.selection = EmojiGridGeometry.selection(
            vm.selection, afterSectionAt: start, changesFrom: old, to: new)
    }

    /// One visual row vertically, spilling into the neighbour by column; one cell horizontally.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        let sections = sections
        let count = sections.reduce(0) { $0 + $1.entries.count }
        guard count > 0 else { return selection }
        switch axis {
        case .vertical:
            let geometry = EmojiGridGeometry(
                counts: sections.map(\.entries.count), columns: columns.rawValue)
            return delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        case .horizontal:
            return min(max(selection + delta, 0), count - 1)
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let sections = sections
        if !index.isLoaded {
            EmptyResults(text: String(localized: "Loading emoji…"))
        } else if sections.isEmpty {
            EmptyResults(text: String(localized: "No emoji found"))
        } else {
            EmojiGridView(
                sections: sections,
                selection: selection,
                tone: tone,
                columns: columns,
                scroll: scroll,
                onSelect: { vm.selection = $0 },
                onActivate: { activate(at: vm.selection) },
                onActions: { flat in
                    vm.selection = flat
                    openActions()
                }
            )
        }
    }

    private func togglePin(_ entry: EmojiEntry) {
        let position = visiblePins.firstIndex(of: entry.glyph)
        pinned.toggle(entry.glyph)
        if let position, pinsLeadGrid, vm.selection == position {
            // The neighbour sliding into the slot takes the selection, not the catalog copy.
            vm.selection = EmojiGridGeometry.selectionAfterRemovingPin(
                at: position, remainingCount: visiblePins.count)
        } else if isBrowsing, vm.emojiCategoryFilter == .all {
            vm.selection = max(vm.selection + (position == nil ? 1 : -1), 0)
        } else if vm.emojiCategoryFilter == .pinned {
            vm.selection = min(vm.selection, max(rows.count - 1, 0))
        }
    }

    private func movePin(_ entry: EmojiEntry, by delta: Int) {
        let pins = visiblePins
        guard let position = pins.firstIndex(of: entry.glyph),
            pins.indices.contains(position + delta)
        else { return }
        pinned.swap(entry.glyph, with: pins[position + delta])
        if pinsLeadGrid, vm.selection == position { vm.selection = position + delta }
    }
}

@MainActor
enum EmojiActionsMenu {
    static func content(
        entry: EmojiEntry, core: AppCore, target: PasteTarget?, pinPosition: Int?, pinCount: Int,
        query: String,
        canZoom: (EmojiGridZoom) -> Bool, togglePin: @escaping () -> Void,
        movePin: @escaping (Int) -> Void, zoom: @escaping (EmojiGridZoom) -> Void
    )
        -> PopoverMenuContent
    {
        let noun = entry.category.itemTitle
        let isPrimaryPaste = core.settings.emojiPrimaryAction == .paste
        let pasteTitle = target?.pasteTitle ?? String(localized: "Paste")
        let copyTitle = String(localized: "Copy to Clipboard")

        var items: [PopoverMenuItem] = []

        // Primary action
        if isPrimaryPaste {
            items.append(PopoverMenuItem(
                title: pasteTitle,
                icon: .paste(target, fallback: "doc.on.clipboard"),
                shortcut: "↵"
            ) {
                core.emojiCoordinator.pasteEmoji(entry, query: query)
            })
            items.append(PopoverMenuItem(
                title: copyTitle,
                systemImage: "doc.on.doc",
                shortcut: "⌘↵"
            ) {
                core.emojiCoordinator.copyEmoji(entry, query: query)
            })
        } else {
            items.append(PopoverMenuItem(
                title: copyTitle,
                systemImage: "doc.on.doc",
                shortcut: "↵"
            ) {
                core.emojiCoordinator.copyEmoji(entry, query: query)
            })
            items.append(PopoverMenuItem(
                title: pasteTitle,
                icon: .paste(target, fallback: "doc.on.clipboard"),
                shortcut: "⌘↵"
            ) {
                core.emojiCoordinator.pasteEmoji(entry, query: query)
            })
        }

        // Paste and Keep Window Open
        items.append(PopoverMenuItem(
            title: String(localized: "Paste and Keep Window Open"),
            icon: .paste(target, fallback: "macwindow"),
            shortcut: "⇧⌘↵"
        ) {
            core.emojiCoordinator.pasteEmojiKeepingWindowOpen(entry, query: query)
        })

        // Skin Tone actions (if supported)
        if entry.supportsSkinTone {
            for tone in EmojiSkinTone.allCases {
                let tonedGlyph = entry.display(tone: tone)
                let isDefault = (tone == .none)
                let toneLabel = tone.title
                items.append(PopoverMenuItem(
                    title: String(localized: "Paste with \(toneLabel) Skin Tone (\(tonedGlyph))"),
                    icon: .paste(target, fallback: "hand.raised"),
                    startsSection: isDefault,
                    shortcut: isDefault ? "⌥⌘V" : nil
                ) {
                    core.emojiCoordinator.pasteEmoji(entry, tone: tone, query: query)
                })
            }

            for tone in EmojiSkinTone.allCases {
                let tonedGlyph = entry.display(tone: tone)
                let isDefault = (tone == .none)
                let toneLabel = tone.title
                items.append(PopoverMenuItem(
                    title: String(localized: "Copy with \(toneLabel) Skin Tone (\(tonedGlyph))"),
                    systemImage: "doc.on.doc",
                    startsSection: isDefault,
                    shortcut: isDefault ? "⌥⌘C" : nil
                ) {
                    core.emojiCoordinator.copyEmoji(entry, tone: tone, query: query)
                })
            }
        }

        // Copy Unicode
        let unicodeScalars = entry.glyph.unicodeScalars
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: " ")
        items.append(PopoverMenuItem(
            title: String(localized: "Copy Unicode"),
            icon: .symbol("number"),
            startsSection: !entry.supportsSkinTone,
            shortcut: "⌥⇧⌘C",
            detail: unicodeScalars,
            action: {
                core.emojiCoordinator.copyUnicode(entry)
            }
        ))

        // Edit Custom Keywords
        items.append(PopoverMenuItem(
            title: String(localized: "Assign Custom Keywords…"),
            systemImage: "tag",
            shortcut: "⌘E"
        ) {
            core.emojiCoordinator.editCustomKeywords(for: entry)
        })

        // Pin/Unpin
        items.append(PopoverMenuItem(
            title: pinPosition == nil
                ? String(localized: "Pin \(noun)") : String(localized: "Unpin \(noun)"),
            systemImage: pinPosition == nil ? "pin" : "pin.slash",
            startsSection: true, shortcut: "⌘.", action: togglePin))

        if let pinPosition {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Move Up in Pinned"), systemImage: "arrow.up",
                    isEnabled: pinPosition > 0, shortcut: "⌥⌘↑"
                ) { movePin(-1) })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Move Down in Pinned"), systemImage: "arrow.down",
                    isEnabled: pinPosition < pinCount - 1, shortcut: "⌥⌘↓"
                ) { movePin(1) })
        }

        // Zoom options
        items.append(contentsOf: [
            PopoverMenuItem(
                title: String(localized: "Actual Size"), systemImage: "magnifyingglass",
                isEnabled: canZoom(.actualSize), startsSection: true, shortcut: "⌘0"
            ) { zoom(.actualSize) },
            PopoverMenuItem(
                title: String(localized: "Zoom In"), systemImage: "plus.magnifyingglass",
                isEnabled: canZoom(.zoomIn), shortcut: "⌘+"
            ) { zoom(.zoomIn) },
            PopoverMenuItem(
                title: String(localized: "Zoom Out"), systemImage: "minus.magnifyingglass",
                isEnabled: canZoom(.zoomOut), shortcut: "⌘-"
            ) { zoom(.zoomOut) }
        ])

        return PopoverMenuContent(header: "\(entry.glyph) \(entry.displayName)", items: items)
    }
}
