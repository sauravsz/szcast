import AppKit
import Foundation

/// Provides the official, high-contrast, dual-mode compatible ChatGPT brand icon.
/// Uses #10A37F emerald green squircle with a crisp pure-white OpenAI rosette.
public enum ChatGPTIconProvider {
    public static let emeraldGreen = NSColor(srgbRed: 16.0 / 255.0, green: 163.0 / 255.0, blue: 127.0 / 255.0, alpha: 1.0) // #10A37F

    /// Generates a pixel-perfect, crisp ChatGPT squircle icon (256x256) with #10A37F emerald background and white rosette.
    public static func generatePNGData(size: CGFloat = 256) -> Data? {
        if let asset = NSImage(named: "BrandChatGPT"),
           let tiff = asset.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: size, height: size)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        // 1. Draw smooth squircle background with official ChatGPT Emerald Green (#10A37F)
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius: CGFloat = size * (56.0 / 256.0)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        emeraldGreen.setFill()
        path.fill()

        // 2. Draw crisp white OpenAI rosette in the center
        let assetImage: NSImage? = NSImage(named: "BrandChatGPT") ?? NSImage(named: "AIBrandOpenAI") ?? {
            let bundle = Bundle.main
            if let url = bundle.url(forResource: "openai", withExtension: "svg") ?? bundle.url(forResource: "AIBrandOpenAI", withExtension: nil) {
                return NSImage(contentsOf: url)
            }
            return nil
        }()

        if let asset = assetImage {
            let glyphSize: CGFloat = size * 0.60
            let glyphRect = NSRect(
                x: (size - glyphSize) / 2,
                y: (size - glyphSize) / 2,
                width: glyphSize,
                height: glyphSize
            )
            let tinted = NSImage(size: NSSize(width: glyphSize, height: glyphSize), flipped: false, drawingHandler: { r in
                asset.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            })
            tinted.draw(in: glyphRect)
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
