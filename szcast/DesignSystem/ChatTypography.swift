import AppKit
import SwiftUI

/// Typographic styles and sizes for AI Chat, with a default base of 14pt.
struct ChatTypography: Sendable, Equatable {
    let baseSize: CGFloat
    let fontFamily: String?
    let codeFontFamily: String?
    let scale: CGFloat

    init(
        baseSize: CGFloat = 14,
        fontFamily: String? = nil,
        codeFontFamily: String? = nil,
        scale: CGFloat = 1
    ) {
        self.baseSize = baseSize
        self.fontFamily = fontFamily
        self.codeFontFamily = codeFontFamily
        self.scale = scale
    }

    var scaledBase: CGFloat {
        scale == 1 ? baseSize : (baseSize * scale).rounded()
    }

    func bodyFont(weight: NSFont.Weight = .regular) -> NSFont {
        resolveNSFont(size: scaledBase, weight: weight, family: fontFamily)
    }

    func headingFont(level: Int) -> NSFont {
        let size: CGFloat
        let weight: NSFont.Weight
        switch level {
        case 1:
            size = (scaledBase * 1.35).rounded()
            weight = .semibold
        case 2:
            size = (scaledBase * 1.15).rounded()
            weight = .semibold
        default:
            size = scaledBase
            weight = .bold
        }
        return resolveNSFont(size: size, weight: weight, family: fontFamily)
    }

    func codeFont(sizeDelta: CGFloat = -1) -> NSFont {
        let size = max(scaledBase + sizeDelta, 9)
        if let codeFontFamily, !codeFontFamily.isEmpty, let font = NSFont(name: codeFontFamily, size: size) {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func captionFont() -> NSFont {
        let size = max((scaledBase * 0.78).rounded(), 9)
        return resolveNSFont(size: size, weight: .regular, family: fontFamily)
    }

    func swiftUIFont(size: CGFloat? = nil, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        let s = size ?? scaledBase
        if monospaced {
            if let codeFontFamily, !codeFontFamily.isEmpty {
                return .custom(codeFontFamily, size: s).weight(weight)
            }
            return .system(size: s, weight: weight, design: .monospaced)
        }
        if let fontFamily, !fontFamily.isEmpty {
            return .custom(fontFamily, size: s).weight(weight)
        }
        return .system(size: s, weight: weight)
    }

    private func resolveNSFont(size: CGFloat, weight: NSFont.Weight = .regular, family: String?) -> NSFont {
        if let family, !family.isEmpty, let custom = NSFont(name: family, size: size) {
            let descriptor = custom.fontDescriptor.addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.weight: weight]
            ])
            return NSFont(descriptor: descriptor, size: size) ?? custom
        }
        return .systemFont(ofSize: size, weight: weight)
    }
}
