import AppKit

/// The window flags `NSHostingController` can't bridge; SwiftUI owns the toolbar and its title.
@MainActor
final class SettingsWindowChrome: WindowChrome {
    private let settings: AppSettings?

    init(settings: AppSettings? = nil) {
        self.settings = settings
    }

    func install(in window: NSWindow) {
        // All three together are what puts the title inline and leading rather than centred.
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        // `.automatic` draws a hairline once content scrolls under the bar, splitting the surface.
        window.titlebarSeparatorStyle = .none
        // Stock Settings isn't dragged by its content — a drag on a `Form` shouldn't move the window.
        window.isMovableByWindowBackground = false

        let glassEnabled = settings?.liquidGlassEnabled ?? true
        if glassEnabled {
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
