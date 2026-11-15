import AppKit
import SwiftUI

struct FinderFileActionsSettingsView: View {
    @State private var service = FinderFileActionsService()

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Finder File Actions")
                            .font(.headline)
                        Text("Quickly move or copy files selected in Finder to pinned or searched folders.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                LabeledContent {
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
                } label: {
                    Text("Manage destinations")
                    Text("Pin frequently used folders to the top of the destination picker.")
                }
            } header: {
                Text("File Actions")
            }

            Section {
                if service.pinnedFolders.isEmpty {
                    Text("No pinned folders configured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                } else {
                    ForEach(service.pinnedFolders, id: \.path) { folder in
                        HStack {
                            Label(folder.lastPathComponent, systemImage: "folder.fill")
                                .font(.headline)
                            Spacer()
                            Text(folder.path)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 240, alignment: .trailing)
                            Button(role: .destructive) {
                                _ = service.togglePin(folder: folder)
                            } label: {
                                Image(systemName: "pin.slash")
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
                LabeledContent {
                    Text("Hyper + M  (⌃⌥⇧⌘M)")
                        .font(.subheadline.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Move file shortcut")
                    Text("Select any file or folder in Finder, then press to trigger the move action.")
                }
            } header: {
                Text("Shortcuts & Triggers")
            }
        }
        .formStyle(.grouped)
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
