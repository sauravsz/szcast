import Foundation

enum DictationPasteMode: String, CaseIterable, Identifiable, Sendable {
    case allAtOnce = "allAtOnce"

    var id: Self { self }

    var title: String {
        switch self {
        case .allAtOnce: String(localized: "All at once after transcribing and cleaning")
        }
    }

    var summary: String {
        switch self {
        case .allAtOnce: String(localized: "Pastes entire transcription at once after speech recognition and S1-mini cleanup complete.")
        }
    }
}
