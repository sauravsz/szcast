import Foundation

enum DictationTranscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case parakeet = "parakeet"
    case groq = "groq"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parakeet:
            return String(localized: "Parakeet (Local Neural Engine)")
        case .groq:
            return String(localized: "Groq Whisper (Cloud)")
        }
    }

    var shortTitle: String {
        switch self {
        case .parakeet: return "Parakeet"
        case .groq: return "Groq Cloud"
        }
    }
}

enum DictationPolishProvider: String, CaseIterable, Identifiable, Sendable {
    case localS1 = "localS1"
    case groq = "groq"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localS1:
            return String(localized: "Local S1-mini (On-Device)")
        case .groq:
            return String(localized: "Groq Llama (Cloud)")
        }
    }

    var shortTitle: String {
        switch self {
        case .localS1: return "Local S1"
        case .groq: return "Groq Llama"
        }
    }
}
