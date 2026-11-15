import AppKit
import SwiftUI

struct FinderFileActionsSettingsView: View {
    @State private var service = FinderFileActionsService()

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Finder File Actions")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Quickly move or copy files selected in Finder to pinned or searched folders.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    HStack(spacing: 12) {
                        Button("Add Pinned Folder…") {
                            addFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if !service.recentFolders.isEmpty {
                            Button("Clear Recent Folders") {
                                service.clearRecent()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("File Actions")
            }

            Section {
                if service.pinnedFolders.isEmpty {
                    Text("No pinned folders configured.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.pinnedFolders, id: \.path) { folder in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                Text(folder.path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                _ = service.togglePin(folder: folder)
                            } label: {
                                Image(systemName: "pin.slash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Unpin folder")
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Pinned Destinations (\(service.pinnedFolders.count))")
            } footer: {
                Text("Pinned folders appear at the top of the destination picker when moving or copying files.")
            }

            Section {
                HStack(spacing: 12) {
                    Text("Move File to Folder Hotkey")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("Hyper + M  (⌃⌥⇧⌘M)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            } header: {
                Text("Shortcuts & Triggers")
            } footer: {
                Text("Select any file or folder in Finder, then press Hyper + M to instantly move it.")
            }
        }
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
