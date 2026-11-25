import AppKit

@MainActor
enum StatsMenuBarRenderer {
    private static let itemHeight: CGFloat = 22
    private static let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .medium)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
    private static let networkFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)

    static func stackedMetricImage(label: String, value: String, minWidth: CGFloat = 34) -> NSImage {
        let topAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.black.withAlphaComponent(0.78)
        ]
        let bottomAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.black
        ]

        let topStr = NSAttributedString(string: label, attributes: topAttrs)
        let bottomStr = NSAttributedString(string: value, attributes: bottomAttrs)

        let topSize = topStr.size()
        let bottomSize = bottomStr.size()
        let width = max(minWidth, ceil(max(topSize.width, bottomSize.width)) + 4)

        let image = NSImage(size: NSSize(width: width, height: itemHeight), flipped: false) { _ in
            topStr.draw(at: NSPoint(x: 2, y: 12.5))
            bottomStr.draw(at: NSPoint(x: 2, y: -1.0))
            return true
        }
        image.isTemplate = true
        return image
    }

    static func networkSpeedImage(download: String, upload: String, minWidth: CGFloat = 52) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: networkFont,
            .foregroundColor: NSColor.black
        ]

        let topStr = NSAttributedString(string: download, attributes: attrs)
        let bottomStr = NSAttributedString(string: upload, attributes: attrs)

        let topSize = topStr.size()
        let bottomSize = bottomStr.size()
        let width = max(minWidth, ceil(max(topSize.width, bottomSize.width)) + 4)

        let image = NSImage(size: NSSize(width: width, height: itemHeight), flipped: false) { _ in
            topStr.draw(at: NSPoint(x: width - topSize.width - 2, y: 10.5))
            bottomStr.draw(at: NSPoint(x: width - bottomSize.width - 2, y: -0.5))
            return true
        }
        image.isTemplate = true
        return image
    }
}
