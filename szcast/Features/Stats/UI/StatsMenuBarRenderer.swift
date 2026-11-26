import AppKit

enum StatsMenuBarContent: Equatable {
    case stackedMetric(label: String, value: String)
    case networkSpeed(download: String, upload: String)
    case battery(percentage: Int, isCharging: Bool, isACConnected: Bool, hasBattery: Bool)
}

@MainActor
enum StatsMenuBarRenderer {
    static let defaultHorizontalPadding: CGFloat = 4
    private static let verticalMargin: CGFloat = 2
    private static let stackedMinContentWidth: CGFloat = 31
    private static let networkMinContentWidth: CGFloat = 48
    private static let batteryBodySize = NSSize(width: 22, height: 12)
    private static let batteryNubGap: CGFloat = 1
    private static let batteryNubSize = NSSize(width: 2, height: 4)

    // Matches exelban/stats Kit/Widgets (Mini.swift, Speed.swift).
    private static let labelFont = NSFont.systemFont(ofSize: 7.0, weight: .light)
    private static let valueFont = NSFont.systemFont(ofSize: 12.0, weight: .regular)
    private static let networkFont = NSFont.systemFont(ofSize: 9.0, weight: .light)

    static func apply(
        content: StatsMenuBarContent,
        accessibilityText: String,
        horizontalPadding: CGFloat = defaultHorizontalPadding,
        to item: NSStatusItem
    ) {
        guard let button = item.button else { return }

        let view: StatsMenuBarItemView
        if let existing = button.subviews.first(where: { $0 is StatsMenuBarItemView }) as? StatsMenuBarItemView {
            view = existing
        } else {
            let created = StatsMenuBarItemView(frame: button.bounds)
            created.autoresizingMask = [.width, .height]
            button.addSubview(created)
            view = created
        }

        let clampedPadding = max(0, horizontalPadding)
        let targetLength = ceil(measuredContentWidth(for: content)) + clampedPadding * 2
        if abs(item.length - targetLength) > 0.5 {
            item.length = targetLength
        }
        if view.frame != button.bounds {
            view.frame = button.bounds
        }

        view.horizontalPadding = clampedPadding
        view.content = content
        button.setAccessibilityLabel(accessibilityText)
    }

    static func measuredContentWidth(for content: StatsMenuBarContent) -> CGFloat {
        switch content {
        case let .stackedMetric(label, value):
            let topW = NSAttributedString(string: label, attributes: [.font: labelFont]).size().width
            let botW = NSAttributedString(string: value, attributes: [.font: valueFont]).size().width
            return max(stackedMinContentWidth, ceil(max(topW, botW)))
        case let .networkSpeed(download, upload):
            let topW = NSAttributedString(string: download, attributes: [.font: networkFont]).size().width.rounded(.up)
            let botW = NSAttributedString(string: upload, attributes: [.font: networkFont]).size().width.rounded(.up)
            return max(networkMinContentWidth, max(topW, botW))
        case .battery:
            return ceil(batteryBodySize.width + 2 + batteryNubSize.width)
        }
    }

    static func draw(
        content: StatsMenuBarContent,
        horizontalPadding: CGFloat = defaultHorizontalPadding,
        in bounds: NSRect
    ) {
        let ink = NSColor.textColor
        let contentHeight = max(14, bounds.height - verticalMargin * 2)
        let baseY = verticalMargin
        let contentWidth = max(1, bounds.width - horizontalPadding * 2)

        switch content {
        case let .stackedMetric(label, value):
            let style = NSMutableParagraphStyle()
            style.alignment = .left
            let topStr = NSAttributedString(
                string: label,
                attributes: [.font: labelFont, .foregroundColor: ink, .paragraphStyle: style]
            )
            let botStr = NSAttributedString(
                string: value,
                attributes: [.font: valueFont, .foregroundColor: ink, .paragraphStyle: style]
            )
            let labelRect = NSRect(x: horizontalPadding, y: baseY + 12, width: contentWidth, height: 7)
            let valueRect = NSRect(x: horizontalPadding, y: baseY + 1, width: contentWidth, height: 13)
            topStr.draw(with: labelRect)
            botStr.draw(with: valueRect)

        case let .networkSpeed(download, upload):
            let style = NSMutableParagraphStyle()
            style.alignment = .right
            let attrs: [NSAttributedString.Key: Any] = [
                .font: networkFont,
                .foregroundColor: ink,
                .paragraphStyle: style
            ]
            let rowHeight = contentHeight / 2.0
            let topStr = NSAttributedString(string: download, attributes: attrs)
            let botStr = NSAttributedString(string: upload, attributes: attrs)
            topStr.draw(with: NSRect(x: horizontalPadding, y: baseY + rowHeight + 1, width: contentWidth, height: rowHeight))
            botStr.draw(with: NSRect(x: horizontalPadding, y: baseY + 1, width: contentWidth, height: rowHeight))

        case let .battery(percentage, isCharging, isACConnected, hasBattery):
            drawBattery(
                percentage: percentage,
                isCharging: isCharging,
                isACConnected: isACConnected,
                hasBattery: hasBattery,
                horizontalPadding: horizontalPadding,
                ink: ink,
                in: bounds
            )
        }
    }

    private static func drawBattery(
        percentage: Int,
        isCharging: Bool,
        isACConnected: Bool,
        hasBattery: Bool,
        horizontalPadding: CGFloat,
        ink: NSColor,
        in bounds: NSRect
    ) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let borderWidth: CGFloat = 1.0
        let halfStroke: CGFloat = 0.5
        let bodyRect = NSRect(
            x: horizontalPadding + borderWidth + halfStroke,
            y: round((bounds.height - batteryBodySize.height) / 2.0) + halfStroke,
            width: batteryBodySize.width - borderWidth,
            height: batteryBodySize.height - borderWidth
        )
        let frameColor = ink.withAlphaComponent(0.5)

        // Isolate `.clear` cutouts inside a transparency layer so the menu bar backdrop stays intact.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { ctx.endTransparencyLayer() }

        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 2.0, yRadius: 2.0)
        bodyPath.lineWidth = borderWidth
        frameColor.setStroke()
        bodyPath.stroke()

        let nubRect = NSRect(
            x: bodyRect.maxX + batteryNubGap,
            y: bodyRect.midY - batteryNubSize.height / 2.0,
            width: batteryNubSize.width,
            height: batteryNubSize.height
        )
        let nubPath = NSBezierPath(roundedRect: nubRect, xRadius: 1.0, yRadius: 1.0)
        frameColor.setFill()
        nubPath.fill()

        if hasBattery {
            let clamped = max(0, min(100, percentage))
            let inset = borderWidth + 1.0 - halfStroke
            let maxWidth = batteryBodySize.width - halfStroke * 2 - borderWidth * 2 - 1.0
            let maxHeight = batteryBodySize.height - halfStroke * 2 - borderWidth * 2 - 1.0
            if clamped > 0 {
                let fillWidth = max(1.0, maxWidth * CGFloat(clamped) / 100.0)
                let fillRect = NSRect(
                    x: bodyRect.minX + inset,
                    y: bodyRect.minY + inset,
                    width: fillWidth,
                    height: maxHeight
                )
                ink.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 1.0, yRadius: 1.0).fill()
            }
        }

        if isCharging {
            drawCutoutOverlay(lightningBoltPath(in: bodyRect), ink: ink, in: ctx)
        } else if isACConnected || !hasBattery {
            drawCutoutOverlay(acPlugPath(in: bodyRect), ink: ink, in: ctx)
        }
    }

    private static func drawCutoutOverlay(_ path: NSBezierPath, ink: NSColor, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        NSColor.black.setFill()
        NSColor.black.setStroke()
        path.fill()
        path.stroke()
        ctx.restoreGState()

        ink.setFill()
        path.fill()
    }

    private static func acPlugPath(in bodyRect: NSRect) -> NSBezierPath {
        let cx = bodyRect.midX
        let cy = bodyRect.midY
        let minY = cy - 7.0
        let maxY = cy + 7.0
        let points: [NSPoint] = [
            NSPoint(x: cx - 1.5, y: minY + 0.5),
            NSPoint(x: cx + 1.5, y: minY + 0.5),
            NSPoint(x: cx + 1.5, y: cy - 2.5),
            NSPoint(x: cx + 4.0, y: cy + 0.5),
            NSPoint(x: cx + 4.0, y: cy + 4.25),
            NSPoint(x: cx + 2.75, y: cy + 4.25),
            NSPoint(x: cx + 2.75, y: maxY - 0.25),
            NSPoint(x: cx + 0.25, y: maxY - 0.25),
            NSPoint(x: cx + 0.25, y: cy + 4.25),
            NSPoint(x: cx - 0.25, y: cy + 4.25),
            NSPoint(x: cx - 0.25, y: maxY - 0.25),
            NSPoint(x: cx - 2.75, y: maxY - 0.25),
            NSPoint(x: cx - 2.75, y: cy + 4.25),
            NSPoint(x: cx - 4.0, y: cy + 4.25),
            NSPoint(x: cx - 4.0, y: cy + 0.5),
            NSPoint(x: cx - 1.5, y: cy - 2.5)
        ]
        let path = NSBezierPath()
        path.move(to: points[0])
        for p in points.dropFirst() { path.line(to: p) }
        path.close()
        return path
    }

    private static func lightningBoltPath(in bodyRect: NSRect) -> NSBezierPath {
        let cx = bodyRect.midX
        let cy = bodyRect.midY
        let halfW: CGFloat = 4.5
        let halfH: CGFloat = 9.0
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx - 3.0, y: cy - halfH))
        path.line(to: NSPoint(x: cx + halfW, y: cy + 1.5))
        path.line(to: NSPoint(x: cx + 1.0, y: cy + 1.5))
        path.line(to: NSPoint(x: cx + 3.0, y: cy + halfH))
        path.line(to: NSPoint(x: cx - halfW, y: cy - 1.5))
        path.line(to: NSPoint(x: cx - 1.0, y: cy - 1.5))
        path.close()
        return path
    }
}

private final class StatsMenuBarItemView: NSView {
    var horizontalPadding: CGFloat = StatsMenuBarRenderer.defaultHorizontalPadding {
        didSet {
            if abs(oldValue - horizontalPadding) > 0.01 {
                needsDisplay = true
            }
        }
    }

    var content: StatsMenuBarContent? {
        didSet {
            if oldValue != content {
                needsDisplay = true
            }
        }
    }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let content else { return }
        StatsMenuBarRenderer.draw(content: content, horizontalPadding: horizontalPadding, in: bounds)
    }
}
