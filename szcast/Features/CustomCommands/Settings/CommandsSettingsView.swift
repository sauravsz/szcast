import SwiftUI

struct CommandsSettingsView: View {
    @Environment(CustomCommandStore.self) private var store
    @Environment(CustomCommandCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            LauncherCategorySwitchSection(
                kind: .command, anchor: .commandsCommands, title: "Enable Commands")

            LauncherItemsSection(
                kind: .command,
                anchor: .commandsCommands,
                searchPrompt: "Search commands…",
                emptyMessage: LocalizedStringResource("commands-empty", defaultValue: "Nothing here yet."))

            ExtensionCommandsSettingsSection()

            FeatureSwitchSection(
                anchor: .commandsCustomCommands,
                enableTitle: "Enable custom commands",
                enableSubtitle: """
                    Run as you in /bin/zsh, or the interpreter a #! line names. \
                    Use full executable paths.
                    """,
                isEnabled: $settings.customCommandsEnabled,
                showsInLauncher: $settings.customCommandsShowInLauncher)

            Section {
                ForEach(CommandCatalog.entries(ownedBy: .commands)) { entry in
                    FeatureCommandRow(entry: entry)
                }
                if store.commands.isEmpty {
                    Text("No custom commands yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedCommands) { command in
                        CustomCommandSettingsRow(
                            command: command,
                            showsInLauncher: settings.customCommandsShowInLauncher,
                            isEnabled: Binding(
                                get: { command.isEnabled },
                                set: {
                                    coordinator.setCustomCommandEnabled(
                                        $0, id: command.id)
                                }),
                            onEdit: { coordinator.editCustomCommand(command) },
                            onDelete: { Task { await coordinator.deleteCustomCommand(id: command.id) } })
                    }
                }
                Button {
                    coordinator.editCustomCommand(nil)
                } label: {
                    SettingsRowTitle(.commandsCustomCommands, "Add Custom Command")
                }
                Button {
                    Task { await coordinator.importScriptDirectory() }
                } label: {
                    SettingsRowTitle(.commandsCustomCommands, "Import Raycast Scripts")
                }
            } footer: {
                Text("Import reads a folder of Raycast script commands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsEnabled(settings.customCommandsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.commands)
        .releasesFocusOnOutsideClick()
    }

    private var sortedCommands: [CustomCommand] {
        store.commands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private struct CustomCommandSettingsRow: View {
    let command: CustomCommand
    let showsInLauncher: Bool
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: command.name, subtitle: command.command) {
            Image(systemName: command.symbol)
        } trailing: {
            if !command.showsInRootSearch {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .help("Hidden from root search")
            }

            // An alias only reaches the ranker through the launcher slice, so it dims with it.
            AliasField(key: command.entryID, name: command.name)
                .settingsEnabled(command.isEnabled && showsInLauncher && command.showsInRootSearch)

            // A disabled command's shortcut fires into the funnel's refusal, so it dims too.
            ShortcutRecorder(action: .customCommand(id: command.id))
                .settingsEnabled(command.isEnabled)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Custom Command")
            .accessibilityLabel("Edit \(command.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Custom Command")
            .accessibilityLabel("Delete \(command.name)")

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Enabled")
                .accessibilityLabel("Enable \(command.name)")
        }
    }
}

private struct ExtensionCommandsSettingsSection: View {
    @Environment(AppIndex.self) private var appIndex
    @Environment(VisibilityStore.self) private var visibility
    @State private var query = ""

    private var entries: [AppEntry] {
        let scoped = appIndex.apps.filter { $0.kind == .extensionCommand }
        guard !query.isEmpty else { return scoped }
        let matched = Set(appIndex.matches(query).map(\.id))
        return scoped.filter { matched.contains($0.id) }
    }

    var body: some View {
        Section {
            if appIndex.apps.contains(where: { $0.kind == .extensionCommand }) {
                SettingsFilterField(prompt: "Search extension commands…", query: $query)
                LauncherItemsList(
                    entries: entries,
                    query: query,
                    isEnabled: visibility.isKindEnabled(.extensionCommand),
                    emptyMessage: LocalizedStringResource("No extension commands found.")
                )
            } else {
                Text("No extension commands installed yet. Install extensions from the Extensions tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Extension Commands")
        } footer: {
            Text("Assign aliases and hotkeys to commands from installed extensions in one central place.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
