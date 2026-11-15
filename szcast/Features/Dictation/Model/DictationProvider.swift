import Foundation

enum DictationTranscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case parakeet = "parakeet"
    case groq = "groq"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parakeet:
            return String(localized: "Parakeet (Local)")
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
            return String(localized: "S1-mini (Local)")
        case .groq:
            return String(localized: "Groq Cloud")
        }
    }

    var shortTitle: String {
        switch self {
        case .localS1: return "Local S1"
        case .groq: return "Groq Llama"
        }
    }
}
