import AppKit
import SwiftUI

private final class AppWindow: NSWindow {
    var closesOnEscape = false
    var minimumContentSize: CGSize = .zero

    override func cancelOperation(_ sender: Any?) {
        if closesOnEscape { close() } else { super.cancelOperation(sender) }
    }

    override func setFrame(_ targetFrame: NSRect, display displayFlag: Bool) {
        var adjusted = targetFrame
        if minimumContentSize.width > 0 {
            let minFrame = self.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
            if adjusted.width < minFrame.width {
                adjusted.size.width = minFrame.width
            }
            if adjusted.height < minFrame.height {
                adjusted.size.height = minFrame.height
            }
        }
        super.setFrame(adjusted, display: displayFlag)
    }
}

/// Built on first show, torn down on close so its SwiftUI tree deallocates. Never quits the app.
@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    private let title: String
    private let contentSize: CGSize
    private let minimumSize: CGSize
    private let isResizable: Bool
    private let autosaveName: String?
    private let activation: ActivationPolicy?
    private let closesOnEscape: Bool
    private var window: NSWindow?
    /// Rebuilt with the window, so a chrome's state never outlives the window it decorated.
    private var chrome: WindowChrome?

    /// The opening size is also the resize floor unless a smaller `minimumSize` is named.
    init(
        title: String, contentSize: CGSize, minimumSize: CGSize? = nil, resizable: Bool = false,
        autosaveName: String? = nil, activation: ActivationPolicy?, closesOnEscape: Bool = false
    ) {
        self.title = title
        self.contentSize = contentSize
        self.minimumSize = minimumSize ?? contentSize
        self.isResizable = resizable
        self.autosaveName = autosaveName
        self.activation = activation
        self.closesOnEscape = closesOnEscape
    }

    /// Returns `true` when a window was built, `false` when an already-open one was re-raised.
    @discardableResult
    func show<Content: View>(
        chrome: WindowChrome? = nil, @ViewBuilder content: () -> Content
    ) -> Bool {
        let root = content()
        return show(chrome: chrome) {
            let hosting = NSHostingController(rootView: root.motionScope())
            // Keep the window's size authoritative: an unconstrained fill would drive the frame.
            hosting.sizingOptions = []
            return hosting
        }
    }

    /// A prebuilt controller; Settings needs one to bridge its SwiftUI toolbar into the window.
    @discardableResult
    func show(chrome: WindowChrome? = nil, contentViewController: () -> NSViewController) -> Bool {
        if let window {
            raise(window)
            return false
        }
        activation?.windowWillOpen()
        let window = makeWindow(content: contentViewController(), chrome: chrome)
        self.chrome = chrome
        self.window = window
        activation?.windowDidOpen(window)
        raise(window)
        return true
    }

    /// Re-raise an open window without rebuilding it; `false` when none is open.
    @discardableResult
    func focus() -> Bool {
        guard let window else { return false }
        raise(window)
        return true
    }

    func close() {
        window?.close()
    }

    /// The title bar sits inside the frame but outside the layout area, so it is added back.
    func fitContent(width: CGFloat, height: CGFloat) {
        guard let window else { return }
        let titlebar = window.frame.height - window.contentLayoutRect.height
        let size = CGSize(width: width, height: height + titlebar)
        guard window.contentMinSize != size else { return }
        let top = window.frame.maxY
        window.contentMinSize = size
        window.setContentSize(size)
        var frame = window.frame
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - NSWindowDelegate

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minFrame = sender.frameRect(forContentRect: NSRect(origin: .zero, size: minimumSize)).size
        return NSSize(
            width: max(frameSize.width, minFrame.width),
            height: max(frameSize.height, minFrame.height)
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        self.window = nil
        self.chrome = nil
        activation?.windowDidClose(window)
    }

    // MARK: - Private

    private func makeWindow(content: NSViewController, chrome: WindowChrome?) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if isResizable { style.insert(.resizable) }
        let window = AppWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.closesOnEscape = closesOnEscape
        // Edge-to-edge under a transparent titlebar, so it reads as one surface.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // AppKit would otherwise resurrect the window at launch, before anything is wired up.
        window.isRestorable = false
        window.minimumContentSize = minimumSize
        window.contentMinSize = minimumSize
        let minFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumSize)).size
        window.minSize = minFrame
        window.delegate = self
        // Before the content: a bridged SwiftUI toolbar restores the title flags it mounted over.
        chrome?.install(in: window)

        window.contentViewController = content
        // `contentViewController` resets the frame to the controller's fitting size.
        window.setContentSize(contentSize)

        if let autosaveName {
            window.setFrameAutosaveName(autosaveName)
            let restored = window.setFrameUsingName(autosaveName)
            let minFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumSize)).size
            if !restored || window.frame.width < minFrameSize.width || window.frame.height < minFrameSize.height {
                window.setContentSize(CGSize(
                    width: max(contentSize.width, minimumSize.width),
                    height: max(contentSize.height, minimumSize.height)
                ))
                window.center()
            }
        } else {
            window.center()
        }
        return window
    }

    private func raise(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // `NSApp.activate` is async, so re-assert next turn — never onto a window closed since.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window, self?.window === window else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
