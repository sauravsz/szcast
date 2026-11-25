import AppKit
import Carbon.HIToolbox
import SwiftUI

private final class StatsPopoverPanel: NSPanel, AnimatedPanel {
    var onEscape: (() -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        followMotion()
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, Int(event.keyCode) == kVK_Escape {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StatsPopoverController: NSObject, NSWindowDelegate {
    private var panel: StatsPopoverPanel?
    private(set) var currentModule: StatsModule?
    private var lastResignDismissal: (module: StatsModule, date: Date)?
    private var anchorRect: NSRect = .zero
    private var screenVisibleFrame: NSRect = .zero
    var onDismiss: (() -> Void)?

    private static let verticalGap: CGFloat = 4
    private static let screenMargin: CGFloat = 8

    func show(
        module: StatsModule,
        anchoredTo button: NSStatusBarButton,
        onOpenMonitor: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        dismiss(notify: false)

        let buttonRect = button.window?.frame ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = button.window?.screen
            ?? NSScreen.screens.first { $0.frame.contains(buttonRect.origin) }
            ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 875)
        let maxHeight = max(240, visibleFrame.height - Self.screenMargin * 2 - Self.verticalGap)

        anchorRect = buttonRect
        screenVisibleFrame = visibleFrame
        currentModule = module

        let initialHeight = min(480, maxHeight)
        let hosting = NSHostingView(
            rootView: StatsPopoverContainerView(
                module: module,
                maxHeight: maxHeight,
                onContentHeightChange: { [weak self] height in
                    self?.resize(toHeight: height)
                },
                onOpenMonitor: { [weak self] in
                    self?.dismiss()
                    onOpenMonitor()
                },
                onOpenSettings: { [weak self] in
                    self?.dismiss()
                    onOpenSettings()
                }
            )
        )
        hosting.sizingOptions = []
        hosting.setFrameSize(NSSize(width: StatsPopoverStyle.width, height: initialHeight))

        let panel = StatsPopoverPanel(content: hosting)
        panel.delegate = self
        panel.onEscape = { [weak self] in
            self?.dismiss()
        }
        self.panel = panel

        place(panel, height: initialHeight)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func wasJustDismissedByResign(module: StatsModule) -> Bool {
        guard let last = lastResignDismissal, last.module == module else { return false }
        let isRecent = Date().timeIntervalSince(last.date) < 0.25
        if isRecent {
            lastResignDismissal = nil
        }
        return isRecent
    }

    func dismiss(notify: Bool = true) {
        guard let closing = panel else {
            currentModule = nil
            return
        }
        panel = nil
        currentModule = nil
        closing.delegate = nil
        closing.onEscape = nil
        closing.orderOut(nil)
        if notify {
            onDismiss?()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let module = currentModule {
            lastResignDismissal = (module, Date())
        }
        dismiss()
    }

    private func resize(toHeight height: CGFloat) {
        guard let panel, height > 0 else { return }
        guard abs(panel.frame.height - height) > 0.5 else { return }
        place(panel, height: height)
    }

    private func place(_ panel: NSPanel, height: CGFloat) {
        let width = StatsPopoverStyle.width
        let centeredX = anchorRect.midX - width / 2
        let minX = screenVisibleFrame.minX + Self.screenMargin
        let maxX = max(minX, screenVisibleFrame.maxX - width - Self.screenMargin)
        let x = min(max(centeredX, minX), maxX)

        let topY = anchorRect.minY - Self.verticalGap
        let minY = screenVisibleFrame.minY + Self.screenMargin
        let y = max(minY, topY - height)

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
