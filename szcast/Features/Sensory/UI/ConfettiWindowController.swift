import AppKit
import QuartzCore

/// Renders a lightweight, non-interactive confetti burst over the active screen.
@MainActor
final class ConfettiWindowController {
    static let shared = ConfettiWindowController()

    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    static let particleImage: CGImage? = {
        let size = CGSize(width: 9, height: 13)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()
    }()

    func burst(screen: NSScreen? = nil) {
        dismissTask?.cancel()
        close()

        guard let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = targetScreen.frame

        let overlayWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.level = .floating
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let hostingView = ConfettiHostingView(frame: CGRect(origin: .zero, size: frame.size))
        overlayWindow.contentView = hostingView
        overlayWindow.orderFrontRegardless()
        window = overlayWindow

        hostingView.startEmission()

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            hostingView.stopEmission()

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                overlayWindow.animator().alphaValue = 0.0
            } completionHandler: { [weak self] in
                self?.close()
            }
        }
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class ConfettiHostingView: NSView {
    private let emitterLayer = CAEmitterLayer()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(emitterLayer)
        setupEmitter()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        emitterLayer.frame = bounds
        emitterLayer.emitterPosition = CGPoint(x: bounds.midX, y: -20)
        emitterLayer.emitterSize = CGSize(width: bounds.width * 0.8, height: 10)
    }

    private func setupEmitter() {
        emitterLayer.emitterShape = .line
        emitterLayer.emitterMode = .outline
        emitterLayer.renderMode = .unordered

        guard let image = ConfettiWindowController.particleImage else { return }

        let colors: [NSColor] = [
            NSColor(srgbRed: 0.95, green: 0.30, blue: 0.30, alpha: 1.0),
            NSColor(srgbRed: 0.20, green: 0.75, blue: 0.70, alpha: 1.0),
            NSColor(srgbRed: 0.25, green: 0.55, blue: 0.95, alpha: 1.0),
            NSColor(srgbRed: 0.98, green: 0.82, blue: 0.20, alpha: 1.0),
            NSColor(srgbRed: 0.65, green: 0.40, blue: 0.90, alpha: 1.0),
            NSColor(srgbRed: 0.30, green: 0.82, blue: 0.45, alpha: 1.0),
        ]

        emitterLayer.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = image
            cell.color = color.cgColor
            cell.birthRate = 25
            cell.lifetime = 3.5
            cell.velocity = 280
            cell.velocityRange = 120
            cell.yAcceleration = 480
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi / 4
            cell.spin = 3.5
            cell.spinRange = 4.0
            cell.scale = 0.8
            cell.scaleRange = 0.4
            return cell
        }
    }

    func startEmission() {
        emitterLayer.birthRate = 1.0
    }

    func stopEmission() {
        emitterLayer.birthRate = 0.0
    }
}
