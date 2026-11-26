import Foundation

enum DictationTranscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case local = "local"
    case cloud = "cloud"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local:
            return String(localized: "Local")
        case .cloud:
            return String(localized: "Cloud")
        }
    }

    var shortTitle: String {
        switch self {
        case .local: return "Local"
        case .cloud: return "Cloud"
        }
    }

    static func fromStored(_ raw: String?) -> Self {
        switch raw?.lowercased() {
        case "cloud", "groq":
            return .cloud
        default:
            return .local
        }
    }
}

enum DictationCloudSpeechProvider: String, CaseIterable, Identifiable, Sendable {
    case groq = "groq"
    case deepgram = "deepgram"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groq:
            return String(localized: "Groq")
        case .deepgram:
            return String(localized: "Deepgram")
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
