import AppKit
import SwiftUI

enum PaletteThemePreset: String, CaseIterable, Identifiable, Sendable {
    case szcastDark = "szcast-dark"
    case oledBlack = "oled-black"
    case nordicSlate = "nordic-slate"
    case warmEspresso = "warm-espresso"
    case studioLight = "studio-light"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .szcastDark: return String(localized: "szcast Dark")
        case .oledBlack: return String(localized: "OLED Black")
        case .nordicSlate: return String(localized: "Nordic Slate")
        case .warmEspresso: return String(localized: "Warm Espresso")
        case .studioLight: return String(localized: "Studio Light")
        }
    }

    var subtitle: String {
        switch self {
        case .szcastDark: return String(localized: "Default balanced neutral dark chrome.")
        case .oledBlack: return String(localized: "True pitch-black background with high contrast for OLED displays.")
        case .nordicSlate: return String(localized: "Cool deep slate blue tones with frosty accents.")
        case .warmEspresso: return String(localized: "Warm earthy charcoal with subtle amber highlights.")
        case .studioLight: return String(localized: "Crisp, airy light mode with dark ink typography.")
        }
    }

    var panelOpaqueBackground: (dark: NSColor, light: NSColor) {
        switch self {
        case .szcastDark:
            return (dark: .srgbInk(0.12, alpha: 1.0), light: .srgbInk(0.96, alpha: 1.0))
        case .oledBlack:
            return (dark: .srgbInk(0.00, alpha: 1.0), light: .srgbInk(0.96, alpha: 1.0))
        case .nordicSlate:
            return (dark: NSColor(srgbRed: 0.07, green: 0.10, blue: 0.15, alpha: 1.0), light: .srgbInk(0.96, alpha: 1.0))
        case .warmEspresso:
            return (dark: NSColor(srgbRed: 0.11, green: 0.09, blue: 0.08, alpha: 1.0), light: .srgbInk(0.96, alpha: 1.0))
        case .studioLight:
            return (dark: .srgbInk(0.12, alpha: 1.0), light: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1.0))
        }
    }

    var panelScrim: (dark: NSColor, light: NSColor) {
        switch self {
        case .szcastDark:
            return (dark: .srgbInk(0, alpha: 0.40), light: .srgbInk(1, alpha: 0.55))
        case .oledBlack:
            return (dark: .srgbInk(0, alpha: 0.65), light: .srgbInk(1, alpha: 0.55))
        case .nordicSlate:
            return (dark: NSColor(srgbRed: 0.04, green: 0.06, blue: 0.09, alpha: 0.50), light: .srgbInk(1, alpha: 0.55))
        case .warmEspresso:
            return (dark: NSColor(srgbRed: 0.06, green: 0.04, blue: 0.03, alpha: 0.50), light: .srgbInk(1, alpha: 0.55))
        case .studioLight:
            return (dark: .srgbInk(0, alpha: 0.40), light: .srgbInk(1, alpha: 0.65))
        }
    }

    var selectionFill: (dark: Double, light: Double) {
        switch self {
        case .szcastDark:
            return (dark: 0.10, light: 0.09)
        case .oledBlack:
            return (dark: 0.15, light: 0.09)
        case .nordicSlate:
            return (dark: 0.13, light: 0.09)
        case .warmEspresso:
            return (dark: 0.13, light: 0.09)
        case .studioLight:
            return (dark: 0.10, light: 0.08)
        }
    }

    var rowHoverFill: (dark: Double, light: Double) {
        switch self {
        case .szcastDark:
            return (dark: 0.05, light: 0.045)
        case .oledBlack:
            return (dark: 0.08, light: 0.045)
        case .nordicSlate:
            return (dark: 0.07, light: 0.045)
        case .warmEspresso:
            return (dark: 0.07, light: 0.045)
        case .studioLight:
            return (dark: 0.05, light: 0.04)
        }
    }

    var borderStroke: (dark: Double, light: Double) {
        switch self {
        case .szcastDark:
            return (dark: 0.20, light: 0.18)
        case .oledBlack:
            return (dark: 0.28, light: 0.18)
        case .nordicSlate:
            return (dark: 0.24, light: 0.18)
        case .warmEspresso:
            return (dark: 0.24, light: 0.18)
        case .studioLight:
            return (dark: 0.20, light: 0.16)
        }
    }

    var separatorStroke: (dark: Double, light: Double) {
        switch self {
        case .szcastDark:
            return (dark: 0.10, light: 0.12)
        case .oledBlack:
            return (dark: 0.18, light: 0.12)
        case .nordicSlate:
            return (dark: 0.14, light: 0.12)
        case .warmEspresso:
            return (dark: 0.14, light: 0.12)
        case .studioLight:
            return (dark: 0.10, light: 0.10)
        }
    }

    var cardFill: (dark: Double, light: Double) {
        switch self {
        case .szcastDark:
            return (dark: 0.05, light: 0.04)
        case .oledBlack:
            return (dark: 0.08, light: 0.04)
        case .nordicSlate:
            return (dark: 0.07, light: 0.04)
        case .warmEspresso:
            return (dark: 0.07, light: 0.04)
        case .studioLight:
            return (dark: 0.05, light: 0.035)
        }
    }

    var controlSurface: (dark: Double, light: Double) {
        switch self {
        case .szcastDark:
            return (dark: 0.10, light: 0.08)
        case .oledBlack:
            return (dark: 0.15, light: 0.08)
        case .nordicSlate:
            return (dark: 0.12, light: 0.08)
        case .warmEspresso:
            return (dark: 0.12, light: 0.08)
        case .studioLight:
            return (dark: 0.10, light: 0.07)
        }
    }

    var swatchPreviewColor: Color {
        switch self {
        case .szcastDark: return Color(red: 0.12, green: 0.12, blue: 0.12)
        case .oledBlack: return Color.black
        case .nordicSlate: return Color(red: 0.07, green: 0.10, blue: 0.15)
        case .warmEspresso: return Color(red: 0.11, green: 0.09, blue: 0.08)
        case .studioLight: return Color(red: 0.97, green: 0.97, blue: 0.98)
        }
    }

    var swatchAccentColor: Color {
        switch self {
        case .szcastDark: return Color(red: 0.525, green: 0.231, blue: 1.0)
        case .oledBlack: return Color.white
        case .nordicSlate: return Color(red: 0.22, green: 0.74, blue: 0.97)
        case .warmEspresso: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .studioLight: return Color.blue
        }
    }
}
