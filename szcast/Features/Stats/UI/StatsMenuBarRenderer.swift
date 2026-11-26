import AppKit

enum StatsMenuBarContent: Equatable {
    case stackedMetric(label: String, value: String)
    case networkSpeed(download: String, upload: String)
    case battery(percentage: Int, isCharging: Bool, isACConnected: Bool, hasBattery: Bool)
}

@MainActor
enum StatsMenuBarRenderer {
    private static let horizontalPadding: CGFloat = 4
    private static let stackedMinContentWidth: CGFloat = 25
    private static let networkMinContentWidth: CGFloat = 30
    private static let batteryBodySize = NSSize(width: 21, height: 11.5)
    private static let batteryNubGap: CGFloat = 1
    private static let batteryNubSize = NSSize(width: 1.75, height: 4.5)

    private static let labelFont = NSFont.systemFont(ofSize: 8.0, weight: .medium)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .bold)
    private static let networkFont = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .semibold)

    static func apply(content: StatsMenuBarContent, accessibilityText: String, to item: NSStatusItem) {
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

        let targetLength = ceil(measuredContentWidth(for: content)) + horizontalPadding * 2
        if abs(item.length - targetLength) > 0.5 {
            item.length = targetLength
        }
        if view.frame != button.bounds {
            view.frame = button.bounds
        }

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
            let topW = NSAttributedString(string: download, attributes: [.font: networkFont]).size().width
            let botW = NSAttributedString(string: upload, attributes: [.font: networkFont]).size().width
            return max(networkMinContentWidth, ceil(max(topW, botW)))
        case .battery:
            return ceil(batteryBodySize.width + batteryNubGap + batteryNubSize.width)
        }
    }

    static func draw(content: StatsMenuBarContent, in bounds: NSRect) {
        let ink = NSColor.textColor
        let stackSpan: CGFloat = 16.0
        let topCapY = round(bounds.midY - stackSpan / 2.0)

        switch content {
        case let .stackedMetric(label, value):
            let topStr = NSAttributedString(
                string: label,
                attributes: [.font: labelFont, .foregroundColor: ink]
            )
            let botStr = NSAttributedString(
                string: value,
                attributes: [.font: valueFont, .foregroundColor: ink]
            )
            let x = horizontalPadding
            let topY = topCapY - (labelFont.ascender - labelFont.capHeight)
            let botCapY = topCapY + stackSpan - valueFont.capHeight
            let botY = botCapY - (valueFont.ascender - valueFont.capHeight)
            topStr.draw(at: NSPoint(x: x, y: topY))
            botStr.draw(at: NSPoint(x: x, y: botY))

        case let .networkSpeed(download, upload):
            let attrs: [NSAttributedString.Key: Any] = [.font: networkFont, .foregroundColor: ink]
            let topStr = NSAttributedString(string: download, attributes: attrs)
            let botStr = NSAttributedString(string: upload, attributes: attrs)
            let rightEdge = bounds.width - horizontalPadding
            let topY = topCapY - (networkFont.ascender - networkFont.capHeight)
            let botCapY = topCapY + stackSpan - networkFont.capHeight
            let botY = botCapY - (networkFont.ascender - networkFont.capHeight)
            topStr.draw(at: NSPoint(x: floor(rightEdge - topStr.size().width), y: topY))
            botStr.draw(at: NSPoint(x: floor(rightEdge - botStr.size().width), y: botY))

        case let .battery(percentage, isCharging, isACConnected, hasBattery):
            drawBattery(
                percentage: percentage,
                isCharging: isCharging,
                isACConnected: isACConnected,
                hasBattery: hasBattery,
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
        ink: NSColor,
        in bounds: NSRect
    ) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bodyTop = round(bounds.midY - batteryBodySize.height / 2.0)
        let bodyRect = NSRect(x: horizontalPadding, y: bodyTop, width: batteryBodySize.width, height: batteryBodySize.height)
        let frameColor = ink.withAlphaComponent(0.55)

        // Isolate `.clear` cutouts inside a transparency layer so the menu bar backdrop stays intact.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { ctx.endTransparencyLayer() }

        let strokeRect = bodyRect.insetBy(dx: 0.625, dy: 0.625)
        let bodyPath = NSBezierPath(roundedRect: strokeRect, xRadius: 2.3, yRadius: 2.3)
        bodyPath.lineWidth = 1.25
        frameColor.setStroke()
        bodyPath.stroke()

        let nubRect = NSRect(
            x: bodyRect.maxX + batteryNubGap,
            y: bounds.midY - batteryNubSize.height / 2.0,
            width: batteryNubSize.width,
            height: batteryNubSize.height
        )
        let nubPath = NSBezierPath(roundedRect: nubRect, xRadius: 0.85, yRadius: 0.85)
        frameColor.setFill()
        nubPath.fill()

        if hasBattery {
            let clamped = max(0, min(100, percentage))
            let maxFillRect = bodyRect.insetBy(dx: 2.0, dy: 2.0)
            if clamped > 0 {
                let fillWidth = max(1.5, maxFillRect.width * CGFloat(clamped) / 100.0)
                let fillRect = NSRect(x: maxFillRect.minX, y: maxFillRect.minY, width: fillWidth, height: maxFillRect.height)
                ink.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 1.2, yRadius: 1.2).fill()
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
        path.lineWidth = 2.0
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
        let topY = bodyRect.minY - 0.5
        let prongH: CGFloat = 2.5
        let prongW: CGFloat = 1.2
        let prongOffset: CGFloat = 1.55

        let path = NSBezierPath()
        path.appendRect(NSRect(x: cx - prongOffset - prongW / 2, y: topY, width: prongW, height: prongH + 0.5))
        path.appendRect(NSRect(x: cx + prongOffset - prongW / 2, y: topY, width: prongW, height: prongH + 0.5))

        let shoulderY = topY + prongH
        let taperY = shoulderY + 3.4
        let neckY = taperY + 2.4
        let stemBottom = bodyRect.maxY + 0.5

        path.move(to: NSPoint(x: cx - 3.1, y: shoulderY))
        path.line(to: NSPoint(x: cx + 3.1, y: shoulderY))
        path.line(to: NSPoint(x: cx + 3.1, y: taperY))
        path.line(to: NSPoint(x: cx + 1.0, y: neckY))
        path.line(to: NSPoint(x: cx + 1.0, y: stemBottom))
        path.line(to: NSPoint(x: cx - 1.0, y: stemBottom))
        path.line(to: NSPoint(x: cx - 1.0, y: neckY))
        path.line(to: NSPoint(x: cx - 3.1, y: taperY))
        path.close()
        return path
    }

    private static func lightningBoltPath(in bodyRect: NSRect) -> NSBezierPath {
        let cx = bodyRect.midX
        let cy = bodyRect.midY
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx + 0.9, y: bodyRect.minY - 0.5))
        path.line(to: NSPoint(x: cx - 2.9, y: cy + 0.6))
        path.line(to: NSPoint(x: cx - 0.1, y: cy + 0.6))
        path.line(to: NSPoint(x: cx - 0.9, y: bodyRect.maxY + 0.5))
        path.line(to: NSPoint(x: cx + 2.9, y: cy - 0.6))
        path.line(to: NSPoint(x: cx + 0.1, y: cy - 0.6))
        path.close()
        return path
    }
}

private final class StatsMenuBarItemView: NSView {
    var content: StatsMenuBarContent? {
        didSet {
            if oldValue != content {
                needsDisplay = true
            }
        }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let content else { return }
        StatsMenuBarRenderer.draw(content: content, in: bounds)
    }
}
