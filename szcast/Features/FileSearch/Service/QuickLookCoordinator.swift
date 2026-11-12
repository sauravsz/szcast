import AppKit
import Foundation
import QuickLookUI

@MainActor
final class QuickLookCoordinator: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate, @unchecked Sendable {
    static let shared = QuickLookCoordinator()

    private(set) var currentURL: URL?
    private weak var activePanel: QLPreviewPanel?
    private var closeObserver: Any?

    var isVisible: Bool {
        activePanel?.isVisible == true
    }

    func toggle(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        self.activePanel = panel
        if panel.isVisible && currentURL == url {
            close()
        } else {
            currentURL = url
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
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        if let panel = activePanel ?? QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
        currentURL = nil
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
                self?.currentURL = nil
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
        false
    }
}
