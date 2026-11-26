import AppKit
import SwiftUI

struct KeePassXCScreen: PaletteScreen {
    let service: KeePassXCService
    let core: AppCore
    let vm: PaletteState

    struct Row: Identifiable {
        let id: String
        let entry: KeePassXCEntry
    }

    var rows: [Row] {
        if let resumed = service.resumedEntry {
            return [Row(id: resumed.id, entry: resumed)]
        }
        return filteredItems.map { Row(id: $0.id, entry: $0) }
    }

    var rowCount: Int {
        if service.resumedEntry != nil {
            return 1
        }
        return filteredItems.count
    }

    var primaryActionTitle: String {
        if service.resumedEntry != nil {
            return String(localized: "Copy Password")
        }
        return String(localized: "Open Account")
    }

    func hasActions(at selection: Int) -> Bool {
        guard service.isConfigured, service.isUnlocked else { return false }
        return service.resumedEntry != nil || filteredItems.indices.contains(selection)
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard service.isConfigured, service.isUnlocked else { return nil }
        let targetEntry: KeePassXCEntry?
        if let resumed = service.resumedEntry {
            targetEntry = resumed
        } else {
            let items = filteredItems
            targetEntry = items.indices.contains(selection) ? items[selection] : nil
        }
        guard let entry = targetEntry else { return nil }

        var menuItems: [PopoverMenuItem] = []
        if service.resumedEntry == nil {
            menuItems.append(
                PopoverMenuItem(
                    title: String(localized: "Open Account"),
                    systemImage: "person.text.rectangle",
                    shortcut: "↵"
                ) {
                    activate(at: selection)
                }
            )
        }
        menuItems.append(contentsOf: [
            PopoverMenuItem(
                title: String(localized: "Copy Password"),
                systemImage: "key",
                startsSection: service.resumedEntry == nil,
                shortcut: "⌘C"
            ) {
                service.handleShortcutCopyPassword(entry: entry)
            },
            PopoverMenuItem(
                title: String(localized: "Copy TOTP"),
                systemImage: "number",
                shortcut: "⌘T"
            ) {
                service.handleShortcutCopyTOTP(entry: entry)
            },
            PopoverMenuItem(
                title: String(localized: "Copy Username"),
                systemImage: "person",
                shortcut: "⌘B"
            ) {
                service.handleShortcutCopyUsername(entry: entry)
            },
            PopoverMenuItem(
                title: String(localized: "Open URL"),
                systemImage: "arrow.up.right.square",
                shortcut: "⌘U"
            ) {
                service.handleShortcutOpenURL(entry: entry)
            }
        ])
        if service.resumedEntry != nil {
            menuItems.append(
                PopoverMenuItem(
                    title: String(localized: "Back to List"),
                    systemImage: "chevron.left",
                    startsSection: true,
                    shortcut: "Esc"
                ) {
                    service.clearResumedEntry()
                }
            )
        }
        return PopoverMenuContent(header: entry.title, items: menuItems)
    }

    private var filteredItems: [KeePassXCEntry] {
        let query = vm.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return service.entries
        }
        let inMemory = service.entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(query) ||
            entry.path.localizedCaseInsensitiveContains(query) ||
            (entry.group?.localizedCaseInsensitiveContains(query) ?? false) ||
            entry.username.localizedCaseInsensitiveContains(query)
        }
        if !inMemory.isEmpty {
            return inMemory
        }
        service.filterEntries(query: query)
        return service.filteredEntries
    }

    func activate(at selection: Int) {
        if let resumed = service.resumedEntry {
            service.handleShortcutCopyPassword(entry: resumed)
            return
        }

        let items = filteredItems
        guard items.indices.contains(selection) else { return }
        let selected = items[selection]
        service.resumedEntry = selected
        service.selectedEntry = selected
        Task { @MainActor in
            _ = try? await service.fetchEntryDetails(entryPath: selected.path)
        }
    }

    func secondary(at selection: Int) -> Bool {
        if let resumed = service.resumedEntry {
            service.handleShortcutCopyUsername(entry: resumed)
            return true
        }
        let items = filteredItems
        guard items.indices.contains(selection) else { return false }
        service.handleShortcutCopyPassword(entry: items[selection])
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                if !service.isConfigured {
                    KeePassXCSetupView(service: service, core: core)
                } else if !service.isUnlocked {
                    KeePassXCUnlockView(service: service, core: core)
                } else if let resumed = service.resumedEntry {
                    KeePassXCEntryDetailView(entry: resumed, service: service, core: core)
                } else {
                    KeePassXCEntryListView(
                        entries: filteredItems,
                        selection: selection,
                        service: service,
                        core: core,
                        onSelect: { idx in activate(at: idx) }
                    )
                }
            }
            .task {
                if service.isConfigured && service.isUnlocked && service.entries.isEmpty {
                    await service.loadEntries()
                }
            }
        )
    }
}

// MARK: - Setup & Unlock Views

private struct KeePassXCSetupView: View {
    let service: KeePassXCService
    let core: AppCore

    @State private var dbPath: String = ""
    @State private var masterPass: String = ""

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
                .padding(.top, Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.xs) {
                Text(String(localized: "Connect KeePassXC Database"))
                    .font(.headline)
                Text(String(localized: "Select your .kdbx database to enable instant search and autofill."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    TextField("Database path (.kdbx)...", text: $dbPath)
                        .textFieldStyle(.roundedBorder)

                    Button(String(localized: "Browse…")) {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = []
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        if panel.runModal() == .OK, let url = panel.url {
                            dbPath = url.path
                        }
                    }
                }

                SecureField("Master Password...", text: $masterPass)
                    .textFieldStyle(.roundedBorder)

                Button(String(localized: "Unlock & Save to Keychain")) {
                    let cleanPath = dbPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanPath.isEmpty else { return }
                    service.databasePath = cleanPath
                    service.masterPassword = masterPass
                    Task { @MainActor in
                        await service.loadEntries()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(dbPath.isEmpty || masterPass.isEmpty)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)

            Spacer()
        }
    }
}

private struct KeePassXCUnlockView: View {
    let service: KeePassXCService
    let core: AppCore
    @State private var password: String = ""

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.orange)
                .padding(.top, Theme.Spacing.xl)

            Text(String(localized: "Unlock KeePassXC Database"))
                .font(.headline)

            VStack(spacing: Theme.Spacing.md) {
                SecureField("Master Password...", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button(String(localized: "Unlock")) {
                    service.masterPassword = password
                    Task { @MainActor in
                        await service.loadEntries()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
            }
            .frame(maxWidth: 320)
            .padding(.bottom, Theme.Spacing.xl)

            Spacer()
        }
    }
}

// MARK: - Detail Card View (Resumed Account State)

private struct KeePassXCEntryDetailView: View {
    let entry: KeePassXCEntry
    let service: KeePassXCService
    let core: AppCore

    @State private var isPasswordRevealed: Bool = false
    @State private var activeEntry: KeePassXCEntry

    init(entry: KeePassXCEntry, service: KeePassXCService, core: AppCore) {
        self.entry = entry
        self.service = service
        self.core = core
        _activeEntry = State(initialValue: entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    service.clearResumedEntry()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(activeEntry.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let group = activeEntry.group {
                        Text(group)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    service.clearResumedEntry()
                } label: {
                    Text(String(localized: "Esc to List"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    // Username row
                    HStack {
                        Label(String(localized: "Username"), systemImage: "person.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)

                        Text(activeEntry.username.isEmpty ? "—" : activeEntry.username)
                            .font(.body)
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            service.handleShortcutCopyUsername(entry: activeEntry)
                        } label: {
                            Label(String(localized: "Copy (⌘B)"), systemImage: "doc.on.doc")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, Theme.Spacing.sm)

                    Divider()

                    // Password row
                    HStack {
                        Label(String(localized: "Password"), systemImage: "key.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)

                        if activeEntry.password.isEmpty {
                            Text(String(localized: "••••••••"))
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                        } else if isPasswordRevealed {
                            Text(activeEntry.password)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        } else {
                            Text(String(repeating: "•", count: max(activeEntry.password.count, 8)))
                                .font(.body.monospaced())
                        }

                        if !activeEntry.password.isEmpty {
                            Button {
                                isPasswordRevealed.toggle()
                            } label: {
                                Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            service.handleShortcutCopyPassword(entry: activeEntry)
                        } label: {
                            Label(String(localized: "Copy (⌘C)"), systemImage: "doc.on.doc")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentColor)
                        .controlSize(.small)
                    }
                    .padding(.vertical, Theme.Spacing.sm)

                    Divider()

                    // TOTP row
                    HStack {
                        Label(String(localized: "TOTP Code"), systemImage: "clock.badge.checkmark")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)

                        Text(String(localized: "One-Time Password"))
                            .font(.body)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            service.handleShortcutCopyTOTP(entry: activeEntry)
                        } label: {
                            Label(String(localized: "Copy TOTP (⌘T)"), systemImage: "number")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, Theme.Spacing.sm)

                    Divider()

                    // URL row
                    HStack {
                        Label(String(localized: "Website"), systemImage: "safari.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)

                        Text(activeEntry.url.isEmpty ? "—" : activeEntry.url)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button {
                            service.handleShortcutOpenURL(entry: activeEntry)
                        } label: {
                            Label(String(localized: "Open URL (⌘U)"), systemImage: "arrow.up.right")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(activeEntry.url.isEmpty)
                    }
                    .padding(.vertical, Theme.Spacing.sm)

                    if !activeEntry.notes.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(String(localized: "Notes"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(activeEntry.notes)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.sm)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
        .task {
            if let full = try? await service.fetchEntryDetails(entryPath: entry.path) {
                activeEntry = full
            }
        }
    }
}

// MARK: - Entry List View

private struct KeePassXCEntryListView: View {
    let entries: [KeePassXCEntry]
    let selection: Int
    let service: KeePassXCService
    let core: AppCore
    let onSelect: (Int) -> Void

    var body: some View {
        if entries.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "key.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(String(localized: "No KeePassXC entries found"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Try a different search term or check database path in Settings."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Theme.Spacing.xxl)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        KeePassXCEntryRow(
                            entry: entry,
                            isSelected: index == selection,
                            onSelect: { onSelect(index) }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }
}

private struct KeePassXCEntryRow: View {
    let entry: KeePassXCEntry
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "key.fill")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.primary : Color.accentColor)
                .frame(width: 28, height: 28)
                .background(
                    isSelected
                        ? Color.clear
                        : Color.accentColor.opacity(0.12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary)

                if let group = entry.group {
                    Text(group)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
