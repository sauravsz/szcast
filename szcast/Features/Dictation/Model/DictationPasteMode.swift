import Foundation

enum DictationPasteMode: String, CaseIterable, Identifiable, Sendable {
    case allAtOnce = "allAtOnce"
    case wordByWord = "wordByWord"
    case characterByCharacter = "characterByCharacter"

    var id: Self { self }

    var title: String {
        switch self {
        case .allAtOnce: String(localized: "All at once (Instant)")
        case .wordByWord: String(localized: "Word by word (Streaming)")
        case .characterByCharacter: String(localized: "Character by character (Typewriter)")
        }
    }

    var summary: String {
        switch self {
        case .allAtOnce: String(localized: "Pastes entire finished transcription at once instantly.")
        case .wordByWord: String(localized: "Types out transcription word by word with streaming cadence.")
        case .characterByCharacter: String(localized: "Types out transcription character by character with typewriter cadence.")
        }
    }
}
