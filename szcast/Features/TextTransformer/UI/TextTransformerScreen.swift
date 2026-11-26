import AppKit
import Carbon.HIToolbox
import SwiftUI

struct TextTransformerScreen: PaletteScreen {
    @ObservedObject var coordinator: TextTransformerCoordinator
    let core: AppCore
    let vm: PaletteState

    struct Row: Identifiable {
        let id: String
        let transform: TextTransformType
    }

    var rows: [Row] {
        let list = coordinator.filteredTransforms(matching: vm.query)
        return list.map { Row(id: $0.rawValue, transform: $0) }
    }

    var primaryActionTitle: String {
        if let target = vm.pasteTarget {
            return target.pasteTitle
        }
        return String(localized: "Paste to Active App")
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard rows.indices.contains(selection) else { return nil }
        let item = rows[selection].transform
        return PopoverMenuContent(
            header: item.title,
            items: [
                PopoverMenuItem(
                    title: primaryActionTitle,
                    systemImage: "doc.on.clipboard",
                    shortcut: "↵"
                ) {
                    activate(at: selection)
                },
                PopoverMenuItem(
                    title: String(localized: "Copy Output"),
                    systemImage: "doc.on.doc",
                    shortcut: "⌘C"
                ) {
                    _ = secondary(at: selection)
                },
                PopoverMenuItem(
                    title: coordinator.isDiffMode
                        ? String(localized: "Stacked View")
                        : String(localized: "Side-by-Side Diff"),
                    systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    startsSection: true,
                    shortcut: "⌘D"
                ) {
                    _ = perform(.duplicate, at: selection)
                },
                PopoverMenuItem(
                    title: String(localized: "Reset Input"),
                    systemImage: "arrow.counterclockwise",
                    shortcut: "⌘R"
                ) {
                    _ = perform(.restart, at: selection)
                }
            ]
        )
    }

    func activate(at selection: Int) {
        guard rows.indices.contains(selection) else { return }
        let item = rows[selection].transform
        coordinator.selectedTransform = item
        let app = NSWorkspace.shared.frontmostApplication
        coordinator.pasteOutput(previousApp: app)
        core.paletteCoordinator.hidePalette()
    }

    func secondary(at selection: Int) -> Bool {
        guard rows.indices.contains(selection) else { return false }
        let item = rows[selection].transform
        coordinator.selectedTransform = item
        coordinator.copyOutput()
        core.showMessage(String(localized: "Copied \(item.title) to Clipboard"), tone: .success)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .copyFile:
            return secondary(at: selection)
        case .restart:
            coordinator.resetToInitial()
            core.showMessage(String(localized: "Reset text to initial input"), tone: .neutral)
            return true
        case .duplicate:
            coordinator.toggleDiffMode()
            core.showMessage(coordinator.isDiffMode ? "Side-by-side Diff View" : "Stacked View", tone: .neutral)
            return true
        default:
            return false
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let activeTransform: TextTransformType = rows.indices.contains(selection)
            ? rows[selection].transform
            : coordinator.selectedTransform

        return AnyView(
            VStack(spacing: 0) {
                // Category Filter Pills
                categoryPillsView
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)

                Divider()
                    .background(Theme.Colors.separator)

                // Split Body: Left List + Right Preview
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        // Left List of Transforms
                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVStack(spacing: 2) {
                                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                        TextTransformRowView(
                                            row: row,
                                            isSelected: index == selection,
                                            activeOutputSnippet: TextTransformEngine.transform(
                                                coordinator.inputText, using: row.transform
                                            )
                                        ) {
                                            coordinator.selectedTransform = row.transform
                                            vm.selection = index
                                        }
                                        .id(index)
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.sm)
                            }
                            .frame(width: max(260, proxy.size.width * 0.44))
                            .onChange(of: selection) { _, newSelection in
                                scrollProxy.scrollTo(newSelection, anchor: .center)
                            }
                        }

                        Divider()
                            .background(Theme.Colors.separator)

                        // Right Live Inspector & Output
                        TextTransformerInspectorView(
                            coordinator: coordinator,
                            activeTransform: activeTransform
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .onAppear {
                coordinator.prepareOnOpen(seedingQuery: vm.query)
            }
        )
    }

    private var categoryPillsView: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(TransformCategory.allCases) { cat in
                let isSelected = coordinator.activeCategory == cat
                Button {
                    coordinator.activeCategory = cat
                    vm.selection = 0
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: cat.sfSymbol)
                            .font(.system(size: 11, weight: .medium))
                        Text(cat.title)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Theme.Colors.selection : Theme.Colors.controlSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cat.title)
            }
            Spacer()
        }
    }
}

private struct TextTransformRowView: View {
    let row: TextTransformerScreen.Row
    let isSelected: Bool
    let activeOutputSnippet: String
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Theme.Colors.controlSurface)
                    .frame(width: 26, height: 26)
                Image(systemName: row.transform.sfSymbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.transform.title)
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(previewSnippet)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(isSelected ? Theme.Colors.selection : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var previewSnippet: String {
        let clean = activeOutputSnippet.replacingOccurrences(of: "\n", with: " ")
        if clean.count > 28 {
            return String(clean.prefix(28)) + "…"
        }
        return clean.isEmpty ? row.transform.subtitle : clean
    }
}

private struct TextTransformerInspectorView: View {
    @ObservedObject var coordinator: TextTransformerCoordinator
    let activeTransform: TextTransformType

    var body: some View {
        let output = TextTransformEngine.transform(coordinator.inputText, using: activeTransform)
        let metrics = TextMetrics(text: output)

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Metrics Bar
            HStack(spacing: Theme.Spacing.sm) {
                metricChip(label: "Chars", value: "\(metrics.characters)")
                metricChip(label: "Words", value: "\(metrics.words)")
                metricChip(label: "Lines", value: "\(metrics.lines)")
                metricChip(label: "Size", value: "\(metrics.bytes) B")
                Spacer()
                Button {
                    coordinator.toggleDiffMode()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: coordinator.isDiffMode ? "square.split.2x1.fill" : "square.split.1x2")
                        Text(coordinator.isDiffMode ? "Diff" : "Stacked")
                    }
                    .font(.caption2)
                    .foregroundStyle(coordinator.isDiffMode ? Color.accentColor : Theme.Colors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(coordinator.isDiffMode ? Color.accentColor.opacity(0.12) : Theme.Colors.controlSurface, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Toggle Side-by-Side Diff Inspector (⌘D)")

                Button {
                    coordinator.resetToInitial()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.controlSurface, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Reset to initial input (⌘R)")
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)

            if coordinator.isDiffMode {
                // Side-by-Side Diff View
                HStack(spacing: 8) {
                    // Left: Input
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("INPUT (\(coordinator.inputText.count) chars)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        ScrollView(.vertical) {
                            Text(coordinator.inputText.isEmpty ? "No input" : coordinator.inputText)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(coordinator.inputText.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(maxHeight: .infinity)
                        .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                    }

                    // Right: Output
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("OUTPUT: \(activeTransform.title.uppercased())")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Button {
                                coordinator.selectedTransform = activeTransform
                                coordinator.copyOutput()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy")
                                }
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        ScrollView(.vertical) {
                            Text(output.isEmpty ? "No output" : output)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(output.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(maxHeight: .infinity)
                        .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
            } else {
                // Stacked View: Input Card
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("INPUT TEXT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            coordinator.clearInput()
                        } label: {
                            Text("Clear")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("Type or paste input text…", text: $coordinator.inputText)
                        .textFieldStyle(.plain)
                        .font(.system(.callout, design: .monospaced))
                        .padding(8)
                        .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                        )
                }
                .padding(.horizontal, Theme.Spacing.md)

                // Stacked View: Output Card
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("OUTPUT: \(activeTransform.title.uppercased())")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Button {
                            coordinator.selectedTransform = activeTransform
                            coordinator.copyOutput()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView(.vertical) {
                        Text(output.isEmpty ? "No output" : output)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(output.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.Colors.border, lineWidth: 1)
                    )
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
            }
        }
    }

    private func metricChip(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.Colors.controlSurface, in: RoundedRectangle(cornerRadius: 4))
    }
}
