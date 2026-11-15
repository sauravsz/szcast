import AppKit

/// The window flags `NSHostingController` can't bridge; SwiftUI owns the toolbar and its title.
@MainActor
final class SettingsWindowChrome: WindowChrome {
    private let settings: AppSettings?

    init(settings: AppSettings? = nil) {
        self.settings = settings
    }

    func install(in window: NSWindow) {
        // Hide AppKit's window title to prevent duplicate/ghost shadow text over SwiftUI's navigation title
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false

        // Settings window header and body are always 100% opaque native macOS surfaces
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
    }
}
