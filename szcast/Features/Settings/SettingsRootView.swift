import SwiftUI

/// A SwiftUI split, not `NSSplitViewController`: only its sidebar gives `.searchable` a soft edge.
struct SettingsRootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SettingsNavigationState.self) private var navigation
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var hostWindow: NSWindow?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebarView()
                // Ahead of the width: applied after it, the column shrinks to AppKit's default.
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(
                    min: Theme.Size.settingsSidebar, ideal: Theme.Size.settingsSidebar,
                    max: Theme.Size.settingsSidebar)
                .scrollContentBackground(.automatic)
        } detail: {
            SettingsDetailView()
                .frame(minWidth: 580)
                .scrollContentBackground(.automatic)
                .navigationTitle(navigation.tab.title)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        ControlGroup {
                            Button("Back", systemImage: "chevron.backward") { navigation.goBack() }
                                .disabled(!navigation.canGoBack)
                            Button("Forward", systemImage: "chevron.forward") { navigation.goForward() }
                                .disabled(!navigation.canGoForward)
                        }
                        .controlGroupStyle(.navigation)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 840, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            WindowReader { window in
                hostWindow = window
                configureWindow(window)
            }
        )
        .onChange(of: columnVisibility) { _, new in
            if new != .all {
                columnVisibility = .all
            }
        }
    }

    private func configureWindow(_ window: NSWindow?) {
        guard let window else { return }
        let minSize = CGSize(width: 840, height: 600)
        let minFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: minSize)).size
        window.minSize = minFrame
        window.contentMinSize = minSize
        if window.frame.width < minFrame.width || window.frame.height < minFrame.height {
            window.setContentSize(CGSize(width: max(window.frame.width, minSize.width), height: max(window.frame.height, minSize.height)))
            window.center()
        }
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
    }
}
