import Foundation

enum S1Tone: String, CaseIterable, Identifiable, Codable, Sendable {
    case casual = "casual"
    case semiCasual = "semi-casual"
    case semiFormal = "semi-formal"
    case formal = "formal"

    var id: Self { self }

    var title: String {
        switch self {
        case .casual: return String(localized: "Casual")
        case .semiCasual: return String(localized: "Semi-casual")
        case .semiFormal: return String(localized: "Semi-formal")
        case .formal: return String(localized: "Formal")
        }
    }
}

enum S1Structure: String, CaseIterable, Identifiable, Codable, Sendable {
    case prose = "prose"
    case lists = "lists"

    var id: Self { self }

    var title: String {
        switch self {
        case .prose: return String(localized: "Prose")
        case .lists: return String(localized: "Lists")
        }
    }
}

enum S1Context: String, CaseIterable, Identifiable, Codable, Sendable {
    case general = "general"
    case email = "email"

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .email: return String(localized: "Email")
        }
    }
}

struct DictationS1Settings: Codable, Sendable, Equatable {
    var enabled: Bool
    var tone: S1Tone
    var structure: S1Structure
    var context: S1Context
    var idleRelease: DictationIdleRelease

    init(
        enabled: Bool,
        tone: S1Tone,
        structure: S1Structure,
        context: S1Context,
        idleRelease: DictationIdleRelease = .tenMinutes
    ) {
        self.enabled = enabled
        self.tone = tone
        self.structure = structure
        self.context = context
        self.idleRelease = idleRelease
    }

    static let `default` = DictationS1Settings(
        enabled: false,
        tone: .semiFormal,
        structure: .prose,
        context: .general,
        idleRelease: .tenMinutes
    )

    var controlLine: String {
        "[Styling: \(tone.rawValue)] [Structure: \(structure.rawValue)] [Context: \(context.rawValue)]"
    }

    static let systemPrompt =
        "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."
}
