import Foundation

enum DisplayTweaksPreset: String, CaseIterable, Identifiable, Sendable {
    case neutral = "Default"
    case gammaControl = "Gamma Control"
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
        case .gammaControl: return "Gamma Control reference: 0.05 Black Point and 0.89 White Point Luminance"
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
        case .gammaControl:
            return Values(red: 1.0, green: 1.0, blue: 1.0, blacks: 0.05, shadows: 0.0, highlights: 0.0, whites: 0.89, contrast: 0.0, brightness: 0.0)
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

    var percentValues: Values {
        switch self {
        case .neutral:
            return Values(red: 50.0, green: 50.0, blue: 50.0, blacks: 0.0, shadows: 50.0, highlights: 50.0, whites: 100.0, contrast: 50.0, brightness: 50.0)
        case .gammaControl:
            return Values(red: 50.0, green: 50.0, blue: 50.0, blacks: 5.0, shadows: 50.0, highlights: 50.0, whites: 89.0, contrast: 50.0, brightness: 50.0)
        case .sCurve:
            return Values(red: 50.0, green: 50.0, blue: 50.0, blacks: 0.0, shadows: 50.0, highlights: 50.0, whites: 100.0, contrast: 65.0, brightness: 50.0)
        case .shadowLift:
            return Values(red: 50.0, green: 50.0, blue: 50.0, blacks: 18.0, shadows: 65.0, highlights: 52.0, whites: 95.0, contrast: 52.0, brightness: 52.0)
        case .nightWarm:
            return Values(red: 55.0, green: 48.0, blue: 36.0, blacks: 5.0, shadows: 55.0, highlights: 42.0, whites: 78.0, contrast: 48.0, brightness: 48.0)
        case .highContrast:
            return Values(red: 50.0, green: 50.0, blue: 50.0, blacks: 0.0, shadows: 45.0, highlights: 58.0, whites: 100.0, contrast: 70.0, brightness: 50.0)
        case .softReading:
            return Values(red: 52.0, green: 49.0, blue: 44.0, blacks: 8.0, shadows: 56.0, highlights: 40.0, whites: 72.0, contrast: 42.0, brightness: 46.0)
        case .seeDark:
            return Values(red: 50.0, green: 50.0, blue: 50.0, blacks: 35.0, shadows: 72.0, highlights: 55.0, whites: 100.0, contrast: 55.0, brightness: 55.0)
        }
    }
}
