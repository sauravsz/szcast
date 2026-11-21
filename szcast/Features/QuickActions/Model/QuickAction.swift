import Foundation

enum QuickAction: Hashable, Identifiable, Sendable {
    case builtIn(BuiltInQuickAction)
    case custom(CustomQuickAction)

    static let fixGrammar = QuickAction.builtIn(.fixGrammar)
    static let rewrite = QuickAction.builtIn(.rewrite)
    static let makeShorter = QuickAction.builtIn(.makeShorter)
    static let makeLonger = QuickAction.builtIn(.makeLonger)
    static let simplify = QuickAction.builtIn(.simplify)
    static let changeTone = QuickAction.builtIn(.changeTone)
    static let translate = QuickAction.builtIn(.translate)
    static let summarize = QuickAction.builtIn(.summarize)
    static let explain = QuickAction.builtIn(.explain)
    static let findActionItems = QuickAction.builtIn(.findActionItems)
    static let convertTypeScript = QuickAction.builtIn(.convertTypeScript)
    static let slackReply = QuickAction.builtIn(.slackReply)
    static let emailReply = QuickAction.builtIn(.emailReply)
    static let summarizeYouTube = QuickAction.builtIn(.summarizeYouTube)

    static let allBuiltIn: [QuickAction] = BuiltInQuickAction.allCases.map(QuickAction.builtIn)

    var id: String {
        switch self {
        case .builtIn(let action): return action.rawValue
        case .custom(let action): return action.entryID
        }
    }

    var builtInAction: BuiltInQuickAction? {
        guard case .builtIn(let action) = self else { return nil }
        return action
    }

    var customAction: CustomQuickAction? {
        guard case .custom(let action) = self else { return nil }
        return action
    }

    var title: String {
        switch self {
        case .builtIn(let action): return action.title
        case .custom(let action): return action.name
        }
    }

    var symbol: String {
        switch self {
        case .builtIn(let action): return action.symbol
        case .custom(let action): return action.symbol
        }
    }

    var progressTitle: String {
        switch self {
        case .builtIn(let action): return action.progressTitle
        case .custom(let action): return action.name + "…"
        }
    }

    var alwaysPreviews: Bool { builtInAction?.alwaysPreviews ?? false }

    var showsDiff: Bool { builtInAction?.showsDiff ?? false }

    var rendersMarkdown: Bool {
        guard let builtIn = builtInAction else { return true }
        switch builtIn {
        case .summarize, .explain, .findActionItems, .convertTypeScript, .slackReply, .emailReply, .summarizeYouTube:
            return true
        default:
            return false
        }
    }

    var usesTranslationFramework: Bool { builtInAction?.usesTranslationFramework ?? false }
}
