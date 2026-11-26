import SwiftUI

struct SnippetsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(SnippetCoordinator.self) private var coordinator
    @Environment(SnippetsStore.self) private var snippetsStore
    @Environment(AppSettings.self) private var settings
    @State private var expandedFolders: Set<String> = []

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
            if topLevelFolders.isEmpty && rootSnippets.isEmpty {
                Text(snippetsStore.state == .loading ? "Loading snippets…" : "No snippets yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(topLevelFolders) { folder in
                    SnippetFolderSettingsNode(
                        folder: folder,
                        expandedFolders: $expandedFolders
                    )
                }
                ForEach(rootSnippets) { record in
                    SnippetSettingsRow(
                        record: record,
                        effectiveKeyword: snippetsStore.effectiveKeyword(for: record),
                        onEdit: { coordinator.editSnippet(record) },
                        onDelete: { Task { await coordinator.deleteSnippet(id: record.id) } })
                }
            }

            LabeledContent {
                Button("New Folder…") {
                    Task { await coordinator.createFolder(parentPath: nil) }
                }
                Button("Add…") { coordinator.editSnippet(nil) }
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

    private var topLevelFolders: [SnippetFolder] {
        snippetsStore.childFolders(in: nil, includeDisabled: true)
    }

    private var rootSnippets: [StoredSnippet] {
        let knownFolders = Set(snippetsStore.folders.map(\.path))
        return snippetsStore.snippets
            .filter { record in
                guard let folder = record.snippet.folder else { return true }
                return !knownFolders.contains(folder)
            }
            .sorted {
                $0.snippet.name.localizedCaseInsensitiveCompare($1.snippet.name) == .orderedAscending
            }
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

private struct SnippetFolderSettingsNode: View {
    @Environment(SnippetCoordinator.self) private var coordinator
    @Environment(SnippetsStore.self) private var snippetsStore
    let folder: SnippetFolder
    @Binding var expandedFolders: Set<String>

    private var childFolders: [SnippetFolder] {
        snippetsStore.childFolders(in: folder.path, includeDisabled: true)
    }

    private var directSnippets: [StoredSnippet] {
        snippetsStore.directSnippets(in: folder.path, includeDisabled: true)
    }

    private var totalCount: Int {
        snippetsStore.snippetCount(in: folder.path, includeDisabled: true)
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedFolders.contains(folder.path) },
            set: { expanded in
                if expanded {
                    expandedFolders.insert(folder.path)
                } else {
                    expandedFolders.remove(folder.path)
                }
            })
    }

    private var metadataSubtitle: String {
        var parts = [String(localized: "\(totalCount) snippets")]
        let effectivePrefix = snippetsStore.effectivePrefix(for: folder.path)
        if !effectivePrefix.isEmpty {
            parts.append(String(localized: "prefix \(effectivePrefix)"))
        }
        if !snippetsStore.isFolderEffectivelyEnabled(folder.path) {
            parts.append(String(localized: "Disabled"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(childFolders) { child in
                SnippetFolderSettingsNode(
                    folder: child,
                    expandedFolders: $expandedFolders)
            }
            ForEach(directSnippets) { record in
                SnippetSettingsRow(
                    record: record,
                    effectiveKeyword: snippetsStore.effectiveKeyword(for: record),
                    onEdit: { coordinator.editSnippet(record) },
                    onDelete: { Task { await coordinator.deleteSnippet(id: record.id) } })
            }
        } label: {
            SettingsRow(title: folder.name, subtitle: metadataSubtitle) {
                SnippetFolderIconView(icon: folder.icon, size: SettingsListMetrics.iconSize)
            } trailing: {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { folder.isEnabled },
                        set: { enabled in
                            Task { await coordinator.setFolderEnabled(enabled, at: folder.path) }
                        })
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(folder.isEnabled ? "Disable Folder" : "Enable Folder")

                Button {
                    coordinator.editSnippet(nil, initialFolder: folder.path)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Snippet in Folder")
                .accessibilityLabel("New Snippet in \(folder.name)")

                if folder.depth < SnippetFolderPath.maxDepth {
                    Button {
                        Task { await coordinator.createFolder(parentPath: folder.path) }
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .help("New Subfolder")
                    .accessibilityLabel("New Subfolder in \(folder.name)")
                }

                Button {
                    coordinator.configureFolder(at: folder.path)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .help("Configure Folder")
                .accessibilityLabel("Configure \(folder.name)")

                Button {
                    Task { await coordinator.deleteFolder(at: folder.path) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete Folder")
                .accessibilityLabel("Delete \(folder.name)")
            }
        }
    }
}

private struct SnippetSettingsRow: View {
    let record: StoredSnippet
    let effectiveKeyword: String?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: record.snippet.name, subtitle: metadata) {
            EntryIconView(source: SnippetFaviconService.resolveIcon(for: record.snippet))
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
        } trailing: {
            // A disabled snippet's shortcut fires into the funnel's refusal, so it dims too.
            ShortcutRecorder(action: .snippet(id: record.id))
                .settingsEnabled(record.snippet.isEnabled)

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
    }

    private var metadata: String {
        let filename = record.fileURL.lastPathComponent
        guard let keyword = effectiveKeyword ?? record.snippet.keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
            !keyword.isEmpty
        else { return filename }
        return "\(keyword) · \(filename)"
    }
}
