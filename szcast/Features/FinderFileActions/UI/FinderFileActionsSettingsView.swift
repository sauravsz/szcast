import AppKit
import SwiftUI

struct FinderFileActionsSettingsView: View {
    @State private var service = FinderFileActionsService()

    var body: some View {
        Form {
            Section {
                SettingsRow(
                    title: "Finder File Actions",
                    subtitle: "Quickly move or copy files selected in Finder to pinned or searched folders."
                ) {
                    SettingsTabIcon(
                        systemImage: "folder.badge.gearshape",
                        tint: .accentColor,
                        size: Theme.Size.settingsRowIcon * 1.5
                    )
                } trailing: {
                    HStack(spacing: 8) {
                        Button("Add Folder…") {
                            addFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                        if !service.recentFolders.isEmpty {
                            Button("Clear Recents") {
                                service.clearRecent()
                            }
                            .controlSize(.regular)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.finderFileActionsFinderFileActions)
            }

            FeatureCommandsSection(owner: .finderFileActions, anchor: .finderFileActionsCommands)

            Section {
                if service.pinnedFolders.isEmpty {
                    Text("No pinned folders configured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                } else {
                    ForEach(service.pinnedFolders, id: \.path) { folder in
                        SettingsRow(
                            title: folder.lastPathComponent,
                            subtitle: folder.path
                        ) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: SettingsListMetrics.iconSize)
                        } trailing: {
                            Button(role: .destructive) {
                                _ = service.togglePin(folder: folder)
                            } label: {
                                Image(systemName: "pin.slash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Unpin folder")
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.finderFileActionsPinned)
            } footer: {
                Text("Pinned folders appear at the top of the destination picker when moving or copying files.")
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.finderFileActions)
        .task {
            service.loadPinned()
            service.loadRecent()
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Pin Folder"

        if panel.runModal() == .OK {
            for url in panel.urls {
                _ = service.togglePin(folder: url)
            }
            service.loadPinned()
        }
    }
}
