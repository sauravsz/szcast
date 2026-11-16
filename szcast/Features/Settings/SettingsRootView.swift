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
        .navigationTitle(navigation.tab.title)
        .background {
            if settings.liquidGlassEnabled {
                ZStack {
                    VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                    Theme.Colors.panelScrim(transparency: settings.liquidGlassTransparency)
                }
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .background(
            WindowReader { window in
                hostWindow = window
                configureWindow(window)
            }
        )
        .onChange(of: settings.liquidGlassEnabled) { _, _ in
            configureWindow(hostWindow)
        }
        .onChange(of: settings.liquidGlassTransparency) { _, _ in
            configureWindow(hostWindow)
        }
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
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        if settings.liquidGlassEnabled {
            window.isOpaque = false
            window.backgroundColor = .clear
        } else {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
        }

        setupToolbarNavigationGap(in: window)
    }

    private func setupToolbarNavigationGap(in window: NSWindow) {
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            attempts += 1
            guard let titlebarView = window.contentView?.superview else {
                if attempts > 30 { timer.invalidate() }
                return
            }
            guard let platter = findToolbarPlatter(in: titlebarView) else {
                if attempts > 30 { timer.invalidate() }
                return
            }
            timer.invalidate()

            applyPlatterOffset(platter)

            platter.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: platter,
                queue: .main
            ) { [weak platter] _ in
                guard let platter else { return }
                applyPlatterOffset(platter)
            }
        }
    }

    private func applyPlatterOffset(_ platter: NSView) {
        let minX: CGFloat = 236.0
        if platter.frame.origin.x < minX {
            var f = platter.frame
            f.origin.x = minX
            platter.frame = f
        }
    }

    private func findToolbarPlatter(in view: NSView) -> NSView? {
        let name = String(describing: type(of: view))
        if name.contains("ToolbarPlatterView") {
            return view
        }
        for sub in view.subviews {
            if let found = findToolbarPlatter(in: sub) { return found }
        }
        return nil
    }
}
