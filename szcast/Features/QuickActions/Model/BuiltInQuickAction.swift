import Foundation

enum BuiltInQuickAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case fixGrammar
    case rewrite
    case makeShorter
    case makeLonger
    case simplify
    case changeTone
    case translate
    case summarize
    case explain
    case findActionItems
    case convertTypeScript
    case slackReply
    case emailReply
    case summarizeYouTube

    var id: String { rawValue }

    var title: String { titleResource.resolved() }

    /// A resource, so a launcher command named after it keeps the English name searchable.
    var titleResource: LocalizedStringResource {
        switch self {
        case .fixGrammar: return "Fix Grammar"
        case .rewrite: return "Improve Writing"
        case .makeShorter: return "Make Shorter"
        case .makeLonger: return "Make Longer"
        case .simplify: return "Simplify"
        case .changeTone: return "Change Tone"
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        case .explain: return "Explain"
        case .findActionItems: return "Find Action Points"
        case .convertTypeScript: return "Convert to TypeScript"
        case .slackReply: return "Slack Reply"
        case .emailReply: return "Email Reply"
        case .summarizeYouTube: return "Summarize YouTube Video"
        }
    }

    var symbol: String {
        switch self {
        case .fixGrammar: return "textformat"
        case .rewrite: return "wand.and.sparkles"
        case .makeShorter: return "arrow.down.right.and.arrow.up.left"
        case .makeLonger: return "arrow.up.left.and.arrow.down.right"
        case .simplify: return "text.bubble"
        case .changeTone: return "slider.horizontal.3"
        case .translate: return "translate"
        case .summarize: return "text.line.3.summary"
        case .explain: return "lightbulb"
        case .findActionItems: return "checklist"
        case .convertTypeScript: return "curlybraces"
        case .slackReply: return "bubble.left.and.bubble.right"
        case .emailReply: return "envelope"
        case .summarizeYouTube: return "play.rectangle"
        }
    }

    var progressTitle: String {
        switch self {
        case .fixGrammar: return String(localized: "Fixing Grammar…")
        case .rewrite: return String(localized: "Improving Writing…")
        case .makeShorter: return String(localized: "Making Shorter…")
        case .makeLonger: return String(localized: "Making Longer…")
        case .simplify: return String(localized: "Simplifying…")
        case .changeTone: return String(localized: "Changing Tone…")
        case .translate: return String(localized: "Translating…")
        case .summarize: return String(localized: "Summarizing…")
        case .explain: return String(localized: "Explaining…")
        case .findActionItems: return String(localized: "Finding Action Points…")
        case .convertTypeScript: return String(localized: "Converting to TypeScript…")
        case .slackReply: return String(localized: "Drafting Slack Reply…")
        case .emailReply: return String(localized: "Drafting Email Reply…")
        case .summarizeYouTube: return String(localized: "Summarizing YouTube Video…")
        }
    }

    var alwaysPreviews: Bool {
        switch self {
        case .summarize, .explain, .findActionItems, .convertTypeScript, .slackReply, .emailReply, .summarizeYouTube:
            return true
        case .fixGrammar, .rewrite, .makeShorter, .makeLonger, .simplify, .changeTone, .translate:
            return false
        }
    }

    var replacesDirectlyByDefault: Bool { self == .fixGrammar }

    var showsDiff: Bool {
        switch self {
        case .fixGrammar, .rewrite, .makeShorter, .makeLonger, .simplify, .changeTone:
            return true
        default:
            return false
        }
    }

    var usesTranslationFramework: Bool { self == .translate }
}
