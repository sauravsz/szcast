import AppKit
import Foundation
import QuickLookUI

@MainActor
final class QuickLookCoordinator: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate, @unchecked Sendable {
    static let shared = QuickLookCoordinator()

    private(set) var currentURL: URL?
    private(set) var isOpenOrOpening = false
    private weak var activePanel: QLPreviewPanel?
    private var closeObserver: Any?

    var isVisible: Bool {
        isOpenOrOpening || (activePanel?.isVisible == true)
    }

    func toggle(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        self.activePanel = panel
        if panel.isVisible && currentURL == url {
            close()
        } else {
            isOpenOrOpening = true
            currentURL = url
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 2)
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
            installCloseObserver(for: panel)
        }
    }

    func updateSelection(url: URL?) {
        guard let panel = activePanel ?? QLPreviewPanel.shared(), panel.isVisible else { return }
        guard let url else {
            close()
            return
        }
        guard currentURL != url else { return }
        currentURL = url
        panel.reloadData()
    }

    func close() {
        isOpenOrOpening = false
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        if let panel = activePanel ?? QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
        currentURL = nil
        // Restore key focus to Palette window if visible
        if let paletteWindow = NSApp.windows.first(where: { $0.isVisible && !($0 is QLPreviewPanel) && $0.level.rawValue >= NSWindow.Level.modalPanel.rawValue }) {
            paletteWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func installCloseObserver(for panel: QLPreviewPanel) {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isOpenOrOpening = false
                self?.currentURL = nil
                if let paletteWindow = NSApp.windows.first(where: { $0.isVisible && !($0 is QLPreviewPanel) && $0.level.rawValue >= NSWindow.Level.modalPanel.rawValue }) {
                    paletteWindow.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let url = currentURL else {
            return URL(fileURLWithPath: "/") as NSURL
        }
        return url as NSURL
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        if event.keyCode == 53 /* Escape */ || event.keyCode == 49 /* Space */ {
            close()
            return true
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "y" {
            close()
            return true
        }
        // Down / Up arrow keys: forward to palette so selection navigates live
        if event.keyCode == 125 || event.keyCode == 126 {
            if let paletteWindow = NSApp.windows.first(where: { $0.isVisible && !($0 is QLPreviewPanel) && $0.level.rawValue >= NSWindow.Level.modalPanel.rawValue }) {
                paletteWindow.sendEvent(event)
                return true
            }
        }
        return false
    }
}
