import Foundation

enum DisplayTweaksPreset: String, CaseIterable, Identifiable, Sendable {
    case neutral = "Default"
    case sCurve = "S-Curve"
    case shadowLift = "Shadow Lift"
    case nightWarm = "Night Warm"
    case highContrast = "High Contrast"
    case softReading = "Soft Reading"
    case seeDark = "See Dark"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .neutral: return "Stock linear gamma (1.0 across all channels)"
        case .sCurve: return "Adds dynamic punch and clarity without color shifts"
        case .shadowLift: return "Lifts black floor and low shadows for dark scenes"
        case .nightWarm: return "Softens blue light and whites for night-time comfort"
        case .highContrast: return "Deepens blacks and sharpens highlights"
        case .softReading: return "Compresses glare and whites for reading text"
        case .seeDark: return "High shadow visibility for dark media and gaming"
        }
    }

    struct Values {
        let red: Double
        let green: Double
        let blue: Double
        let blacks: Double
        let shadows: Double
        let highlights: Double
        let whites: Double
        let contrast: Double
        let brightness: Double
    }

    var values: Values {
        switch self {
        case .neutral:
            return Values(red: 1.0, green: 1.0, blue: 1.0, blacks: 0.0, shadows: 0.0, highlights: 0.0, whites: 0.0, contrast: 0.0, brightness: 0.0)
        case .sCurve:
            return Values(red: 1.0, green: 1.0, blue: 1.0, blacks: 0.0, shadows: 0.0, highlights: 0.0, whites: 0.0, contrast: 0.25, brightness: 0.0)
        case .shadowLift:
            return Values(red: 1.0, green: 1.0, blue: 1.0, blacks: 0.18, shadows: 0.32, highlights: 0.05, whites: -0.05, contrast: 0.05, brightness: 0.02)
        case .nightWarm:
            return Values(red: 1.05, green: 0.95, blue: 0.72, blacks: 0.05, shadows: 0.10, highlights: -0.15, whites: -0.22, contrast: -0.05, brightness: -0.02)
        case .highContrast:
            return Values(red: 1.0, green: 1.0, blue: 1.0, blacks: -0.15, shadows: -0.10, highlights: 0.15, whites: 0.10, contrast: 0.40, brightness: 0.0)
        case .softReading:
            return Values(red: 1.02, green: 0.98, blue: 0.88, blacks: 0.08, shadows: 0.12, highlights: -0.20, whites: -0.28, contrast: -0.15, brightness: -0.04)
        case .seeDark:
            return Values(red: 1.0, green: 1.0, blue: 1.0, blacks: 0.35, shadows: 0.45, highlights: 0.10, whites: 0.0, contrast: 0.10, brightness: 0.05)
        }
    }
}
