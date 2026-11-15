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
                .scrollContentBackground(settings.liquidGlassEnabled ? .hidden : .automatic)
        } detail: {
            SettingsDetailView()
                .frame(minWidth: 580)
                .scrollContentBackground(settings.liquidGlassEnabled ? .hidden : .automatic)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 840, minHeight: 600)
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
        .background {
            if settings.liquidGlassEnabled {
                ZStack {
                    Color.clear
                        .glassEffect(.regular, in: Rectangle())
                    Theme.Colors.panelScrim(transparency: settings.liquidGlassTransparency)
                }
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .background(
            WindowReader { window in
                hostWindow = window
                applyWindowGlass(to: window, enabled: settings.liquidGlassEnabled)
            }
        )
        .onChange(of: settings.liquidGlassEnabled) { _, enabled in
            applyWindowGlass(to: hostWindow, enabled: enabled)
        }
    }

    private func applyWindowGlass(to window: NSWindow?, enabled: Bool) {
        guard let window else { return }
        window.minSize = CGSize(width: 840, height: 600)
        window.contentMinSize = CGSize(width: 840, height: 600)
        if window.frame.width < 840 || window.frame.height < 600 {
            window.setContentSize(CGSize(width: max(window.frame.width, 840), height: max(window.frame.height, 600)))
            window.center()
        }
        if enabled {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
        } else {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
        }
    }
}
