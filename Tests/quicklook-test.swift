import Foundation
import QuickLookUI

@main
struct QuickLookTest {
    static func main() async {
        let shortcut = PaletteShortcut.resolve(
            command: true, shift: false, option: false, control: false, isDeleteKey: false,
            matches: { $0 == "y" })
        check(shortcut == .quickLook ? "true" : "false", "true")
        check(PaletteShortcut.quickLook.requiresExpanded ? "true" : "false", "true")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-quicklook.txt")
        try? "test quick look content".write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        await MainActor.run {
            let coordinator = QuickLookCoordinator.shared
            check(coordinator.numberOfPreviewItems(in: nil).description, "0")
            coordinator.toggle(url: temp)
            check(coordinator.numberOfPreviewItems(in: nil).description, "1")
            check(((coordinator.previewPanel(nil, previewItemAt: 0) as? NSURL)?.path) ?? "", temp.path)
            coordinator.close()
            check(coordinator.numberOfPreviewItems(in: nil).description, "0")
        }
    }

    private static func check(_ actual: String, _ expected: String) {
        guard actual == expected else {
            fatalError("Expected '\(expected)' but got '\(actual)'")
        }
    }
}
