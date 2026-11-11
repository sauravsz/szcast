import Foundation

enum DictationOtherAudioMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case continueAudio = "continue"
    case lower = "lower"
    case mute = "mute"
    case pause = "pause"

    var id: Self { self }

    var title: String {
        switch self {
        case .continueAudio: return String(localized: "Continue")
        case .lower: return String(localized: "Lower")
        case .mute: return String(localized: "Mute")
        case .pause: return String(localized: "Pause")
        }
    }

    var summary: String {
        switch self {
        case .continueAudio:
            return String(localized: "Music and other audio keep playing as they are.")
        case .lower:
            return String(localized: "Lowers volume to ~20% while you dictate, then restores it.")
        case .mute:
            return String(localized: "Silences other audio while you dictate, then restores volume.")
        case .pause:
            return String(localized: "Pauses whatever is playing, then resumes when you stop.")
        }
    }
}
