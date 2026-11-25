import Foundation

enum CommandID: String, CaseIterable, Sendable {
    /// The palette's chat keeps the id it shipped with, so its hotkeys and fallback still reach it.
    case quickAI = "command:ai-chat"
    case aiChat = "command:ai-chat-window"
    case fixGrammar = "command:fix-grammar"
    case rewrite = "command:rewrite"
    case makeShorter = "command:make-shorter"
    case makeLonger = "command:make-longer"
    case simplify = "command:simplify"
    case changeTone = "command:change-tone"
    case toneProfessional = "command:tone-professional"
    case toneCasual = "command:tone-casual"
    case toneDirect = "command:tone-direct"
    case toneAcademic = "command:tone-academic"
    case toneDiplomatic = "command:tone-diplomatic"
    case translate = "command:translate"
    case summarize = "command:summarize"
    case explain = "command:explain"
    case findActionItems = "command:find-action-items"
    case convertTypeScript = "command:convert-typescript"
    case slackReply = "command:slack-reply"
    case emailReply = "command:email-reply"
    case summarizeYouTube = "command:summarize-youtube"
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case pasteSequentially = "command:paste-sequentially"
    case searchEmoji = "command:search-emoji"
    case searchFiles = "command:search-files"
    case searchMenuItems = "command:search-menu-items"
    case switchWindows = "command:switch-windows"
    case switchWindowsBackwards = "command:switch-windows-backwards"
    case openCamera = "command:open-camera"
    case openInBrowser = "command:open-in-browser"
    case runShellCommand = "command:run-shell-command"
    case createCustomCommand = "command:create-custom-command"
    case searchCustomCommands = "command:search-custom-commands"
    case define = "command:define"
    case joinNextMeeting = "command:join-next-meeting"
    case mySchedule = "command:my-schedule"
    case createEvent = "command:create-event"
    case copyMeetingLink = "command:copy-meeting-link"
    case openInCalendar = "command:open-in-calendar"
    case showNotes = "command:show-notes"
    case createNote = "command:create-note"
    case searchNotes = "command:search-notes"
    case createWindowLayout = "command:create-window-layout"
    case captureWindowLayout = "command:capture-window-layout"
    case switchRoom = "command:switch-room"
    case createRoom = "command:create-room"
    case createQuicklink = "command:create-quicklink"
    case searchQuicklinks = "command:search-quicklinks"
    case importQuicklinks = "command:import-quicklinks"
    case exportQuicklinks = "command:export-quicklinks"
    case searchSnippets = "command:search-snippets"
    case createSnippet = "command:create-snippet"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case checkForUpdates = "command:check-for-updates"
    case settings = "command:settings"
    case about = "command:about"
    case changelog = "command:changelog"
    case support = "command:support"
    case focusTimer = "command:focus-timer"
    case captureScreenText = "command:capture-screen-text"
    case askAIAboutScreenArea = "command:ask-ai-about-screen-area"
    case scanQRCode = "command:scan-qr-code"
    case cleanClipboardURL = "command:clean-clipboard-url"
    case enteAuth = "command:ente-auth"
    case generateDuckAddress = "command:generate-duck-address"
    case cleanKeyboard = "command:clean-keyboard"
    case keepassxc = "command:keepassxc"
    case textTransformer = "command:text-transformer"
    case systemStats = "command:system-stats"
    case dictationInsights = "command:dictation-insights"
    case transcriptStudio = "command:transcript-studio"
    case recordMeeting = "command:record-meeting"
    case transcribeMediaURL = "command:transcribe-media-url"
    case quit = "command:quit"

    static let defaultCompactBarCommands: [CommandID] = [
        .clipboardHistory, .searchEmoji, .searchFiles, .searchQuicklinks
    ]

    static let compactBarOptions: [CommandID] =
        defaultCompactBarCommands + [
            .searchSnippets, .showNotes, .mySchedule, .quickAI
        ]

    static let compactBarLimit = 4

    static func validCompactBarCommands(_ commands: [CommandID]) -> Bool {
        commands.count <= compactBarLimit && Set(commands).count == commands.count
            && commands.allSatisfy(compactBarOptions.contains)
    }

    static func compactBarCommands(from identifiers: [String]) -> [CommandID]? {
        let commands = identifiers.compactMap(CommandID.init(rawValue:))
        guard commands.count == identifiers.count, validCompactBarCommands(commands) else { return nil }
        return commands
    }

    var name: String { nameResource.resolved() }

    var englishName: String { nameResource.key }

    private var nameResource: LocalizedStringResource {
        switch self {
        case .quickAI: return "Quick AI"
        case .aiChat: return "AI Chat"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.titleResource
        case .rewrite: return BuiltInQuickAction.rewrite.titleResource
        case .makeShorter: return BuiltInQuickAction.makeShorter.titleResource
        case .makeLonger: return BuiltInQuickAction.makeLonger.titleResource
        case .simplify: return BuiltInQuickAction.simplify.titleResource
        case .changeTone: return BuiltInQuickAction.changeTone.titleResource
        case .toneProfessional: return BuiltInQuickAction.toneProfessional.titleResource
        case .toneCasual: return BuiltInQuickAction.toneCasual.titleResource
        case .toneDirect: return BuiltInQuickAction.toneDirect.titleResource
        case .toneAcademic: return BuiltInQuickAction.toneAcademic.titleResource
        case .toneDiplomatic: return BuiltInQuickAction.toneDiplomatic.titleResource
        case .translate: return BuiltInQuickAction.translate.titleResource
        case .summarize: return BuiltInQuickAction.summarize.titleResource
        case .explain: return BuiltInQuickAction.explain.titleResource
        case .findActionItems: return BuiltInQuickAction.findActionItems.titleResource
        case .convertTypeScript: return BuiltInQuickAction.convertTypeScript.titleResource
        case .slackReply: return BuiltInQuickAction.slackReply.titleResource
        case .emailReply: return BuiltInQuickAction.emailReply.titleResource
        case .summarizeYouTube: return BuiltInQuickAction.summarizeYouTube.titleResource
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .pasteSequentially: return "Paste Sequentially"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .searchFiles: return "Search Files"
        case .searchMenuItems: return "Search Menu Bar Items"
        case .switchWindows: return "Switch Windows"
        case .switchWindowsBackwards: return "Switch Windows Backwards"
        case .openCamera: return "Open Camera"
        case .openInBrowser: return "Open in Browser"
        case .runShellCommand: return "Run Shell Command"
        case .createCustomCommand: return "Create Custom Command"
        case .searchCustomCommands: return "Search Custom Commands"
        case .define: return "Define Word"
        case .joinNextMeeting: return "Join Next Meeting"
        case .mySchedule: return "My Schedule"
        case .createEvent: return "Create Event"
        case .copyMeetingLink: return "Copy Meeting Link"
        case .openInCalendar: return "Open in Calendar"
        case .showNotes: return "Show Notes"
        case .createNote: return "Create Note"
        case .searchNotes: return "Search Notes"
        case .createWindowLayout: return "Create Window Layout"
        case .captureWindowLayout: return "Create Layout from Current Windows"
        case .switchRoom: return "Switch Room"
        case .createRoom: return "Create Room"
        case .createQuicklink: return "Create Quicklink"
        case .searchQuicklinks: return "Search Quicklinks"
        case .importQuicklinks: return "Import Quicklinks"
        case .exportQuicklinks: return "Export Quicklinks"
        case .searchSnippets: return "Search Snippets"
        case .createSnippet: return "Create Snippet"
        case .exportSettings: return "Export Backup"
        case .importSettings: return "Import Backup"
        case .importFromRaycast: return "Import from Raycast"
        case .checkForUpdates: return "Check for Updates"
        case .settings: return "szcast Settings"
        case .about: return "About szcast"
        case .changelog: return "Changelog"
        case .support: return "Support szcast"
        case .focusTimer: return "Focus Timer"
        case .captureScreenText: return "Capture Screen Text (OCR)"
        case .askAIAboutScreenArea: return "Ask AI About Screen Area"
        case .scanQRCode: return "Scan QR Code"
        case .cleanClipboardURL: return "Clean URL in Clipboard"
        case .enteAuth: return "Ente Auth (2FA)"
        case .generateDuckAddress: return "Generate DuckDuckGo Email"
        case .cleanKeyboard: return "Clean Keyboard Mode"
        case .keepassxc: return "KeePassXC Passwords"
        case .textTransformer: return "Text Transformer"
        case .systemStats: return "System Stats"
        case .dictationInsights: return "Dictation Insights"
        case .transcriptStudio: return "Open Transcript Studio"
        case .recordMeeting: return "Toggle Meeting Recording"
        case .transcribeMediaURL: return "Transcribe URL / Podcast"
        case .quit: return "Quit szcast"
        }
    }

    var sfSymbol: String {
        switch self {
        case .quickAI: return "sparkles"
        case .aiChat: return "bubble.left.and.bubble.right"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.symbol
        case .rewrite: return BuiltInQuickAction.rewrite.symbol
        case .makeShorter: return BuiltInQuickAction.makeShorter.symbol
        case .makeLonger: return BuiltInQuickAction.makeLonger.symbol
        case .simplify: return BuiltInQuickAction.simplify.symbol
        case .changeTone: return BuiltInQuickAction.changeTone.symbol
        case .toneProfessional: return BuiltInQuickAction.toneProfessional.symbol
        case .toneCasual: return BuiltInQuickAction.toneCasual.symbol
        case .toneDirect: return BuiltInQuickAction.toneDirect.symbol
        case .toneAcademic: return BuiltInQuickAction.toneAcademic.symbol
        case .toneDiplomatic: return BuiltInQuickAction.toneDiplomatic.symbol
        case .translate: return BuiltInQuickAction.translate.symbol
        case .summarize: return BuiltInQuickAction.summarize.symbol
        case .explain: return BuiltInQuickAction.explain.symbol
        case .findActionItems: return BuiltInQuickAction.findActionItems.symbol
        case .convertTypeScript: return BuiltInQuickAction.convertTypeScript.symbol
        case .slackReply: return BuiltInQuickAction.slackReply.symbol
        case .emailReply: return BuiltInQuickAction.emailReply.symbol
        case .summarizeYouTube: return BuiltInQuickAction.summarizeYouTube.symbol
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .pasteSequentially: return "list.bullet.clipboard"
        case .searchEmoji: return "face.smiling"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .searchMenuItems: return "menubar.rectangle"
        case .switchWindows, .switchWindowsBackwards: return "macwindow.on.rectangle"
        case .openCamera: return "camera"
        case .openInBrowser: return "globe"
        case .runShellCommand: return "terminal"
        case .createCustomCommand: return "terminal"
        case .searchCustomCommands: return "terminal"
        case .define: return "book.closed"
        case .joinNextMeeting: return "video.fill"
        case .mySchedule: return "calendar"
        case .createEvent: return "calendar.badge.plus"
        case .copyMeetingLink: return "link"
        case .openInCalendar: return "calendar.badge.clock"
        case .showNotes: return "text.page"
        case .createNote: return "note.text.badge.plus"
        case .searchNotes: return "text.magnifyingglass"
        case .createWindowLayout: return "plus.rectangle.on.rectangle"
        case .captureWindowLayout: return "macwindow.badge.plus"
        case .switchRoom: return "door.left.hand.open"
        case .createRoom: return "rectangle.stack.badge.plus"
        case .createQuicklink: return "link.badge.plus"
        case .searchQuicklinks: return Quicklink.sfSymbol
        case .importQuicklinks: return "square.and.arrow.down"
        case .exportQuicklinks: return "square.and.arrow.up"
        case .searchSnippets: return "curlybraces"
        case .createSnippet: return "plus.rectangle.on.rectangle"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .importFromRaycast: return "arrow.down.doc"
        case .checkForUpdates: return "arrow.down.circle"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .changelog: return "clock.arrow.circlepath"
        case .support: return "heart"
        case .focusTimer: return "timer"
        case .captureScreenText: return "text.viewfinder"
        case .askAIAboutScreenArea: return "viewfinder"
        case .scanQRCode: return "qrcode.viewfinder"
        case .cleanClipboardURL: return "link.badge.plus"
        case .enteAuth: return "key.fill"
        case .generateDuckAddress: return "envelope.badge.shield.half.filled"
        case .cleanKeyboard: return "lock.shield"
        case .keepassxc: return "lock.fill"
        case .textTransformer: return "text.word.spacing"
        case .systemStats: return "gauge.with.needle"
        case .dictationInsights: return "chart.bar.xaxis"
        case .transcriptStudio: return "text.bubble.rtl"
        case .recordMeeting: return "record.circle"
        case .transcribeMediaURL: return "link.badge.plus"
        case .quit: return "power"
        }
    }

    /// Exhaustive, so an added shipped action cannot reach the launcher without a row here.
    init(_ action: BuiltInQuickAction) {
        switch action {
        case .fixGrammar: self = .fixGrammar
        case .rewrite: self = .rewrite
        case .makeShorter: self = .makeShorter
        case .makeLonger: self = .makeLonger
        case .simplify: self = .simplify
        case .changeTone: self = .changeTone
        case .toneProfessional: self = .toneProfessional
        case .toneCasual: self = .toneCasual
        case .toneDirect: self = .toneDirect
        case .toneAcademic: self = .toneAcademic
        case .toneDiplomatic: self = .toneDiplomatic
        case .translate: self = .translate
        case .summarize: self = .summarize
        case .explain: self = .explain
        case .findActionItems: self = .findActionItems
        case .convertTypeScript: self = .convertTypeScript
        case .slackReply: self = .slackReply
        case .emailReply: self = .emailReply
        case .summarizeYouTube: self = .summarizeYouTube
        }
    }

    var builtInQuickAction: BuiltInQuickAction? {
        switch self {
        case .fixGrammar: return .fixGrammar
        case .rewrite: return .rewrite
        case .makeShorter: return .makeShorter
        case .makeLonger: return .makeLonger
        case .simplify: return .simplify
        case .changeTone: return .changeTone
        case .toneProfessional: return .toneProfessional
        case .toneCasual: return .toneCasual
        case .toneDirect: return .toneDirect
        case .toneAcademic: return .toneAcademic
        case .toneDiplomatic: return .toneDiplomatic
        case .translate: return .translate
        case .summarize: return .summarize
        case .explain: return .explain
        case .findActionItems: return .findActionItems
        case .convertTypeScript: return .convertTypeScript
        case .slackReply: return .slackReply
        case .emailReply: return .emailReply
        case .summarizeYouTube: return .summarizeYouTube
        default: return nil
        }
    }

    /// Queries this command wins until the user opens a rival more.
    var boostedTerms: Set<String> {
        switch self {
        case .quickAI: ["ai"]
        case .aiChat: ["chat"]
        case .askAIAboutScreenArea: ["ask ai", "screen area", "screenshot", "screen ocr", "vision", "ask about screen", "marquee"]
        case .focusTimer: ["focus", "pomodoro", "timer"]
        case .captureScreenText: ["ocr", "screen text", "grab text", "text recognition"]
        case .scanQRCode: ["qr", "scan qr", "barcode", "scan barcode"]
        case .cleanClipboardURL: ["clean url", "clean link", "sanitize url", "strip tracking"]
        case .enteAuth: ["2fa", "totp", "ente", "authenticator", "otp", "auth"]
        case .generateDuckAddress: ["duck", "duckduckgo", "email", "alias", "private email", "duck address"]
        case .cleanKeyboard: ["clean keyboard", "lock keyboard", "wipe keyboard", "clean"]
        case .keepassxc: ["keepass", "keepassxc", "kdbx", "password", "passwords", "credentials", "vault"]
        case .textTransformer: ["transform", "casing", "camelcase", "snakecase", "json", "prettify", "base64", "urlencode", "hex", "slugify"]
        case .systemStats: ["stats", "system stats", "cpu", "ram", "memory", "battery", "hardware", "disk", "activity monitor", "processes"]
        case .dictationInsights: ["insights", "wpm", "words per minute", "dictation insights", "dictation dashboard", "streak"]
        case .transcriptStudio: ["transcript", "transcript studio", "recordings", "diarization", "srt", "vtt", "dapt", "meeting notes"]
        case .recordMeeting: ["record meeting", "notetaker", "meeting", "system audio"]
        case .transcribeMediaURL: ["youtube", "podcast", "apple podcasts", "url", "yt-dlp", "transcribe url"]
        case .showNotes: ["scratchpad", "notes", "notepad", "sticky note", "floating note"]
        case .changelog: ["changelog", "whats new", "what's new", "release notes", "version", "changes", "updates"]
        case .fixGrammar: ["quick fix", "quickfix", "grammar", "spell", "spelling", "proofread", "typos"]
        case .rewrite: ["improve", "improve writing", "polish", "clarity", "rephrase"]
        case .makeShorter: ["short", "shorter", "condense", "trim", "brief"]
        case .makeLonger: ["longer", "expand", "elaborate", "more"]
        case .simplify: ["simplify", "plain", "clear", "simpler"]
        case .changeTone: ["tone", "change tone", "tone of voice"]
        case .toneProfessional: ["professional", "formal", "executive", "tone professional", "corporate"]
        case .toneCasual: ["casual", "friendly", "informal", "tone casual", "conversational"]
        case .toneDirect: ["direct", "concise", "blunt", "tone direct", "straightforward", "assertive"]
        case .toneAcademic: ["academic", "scholarly", "technical", "tone academic", "rigorous"]
        case .toneDiplomatic: ["diplomatic", "polite", "tactful", "tone diplomatic", "empathetic"]
        case .explain: ["explain", "explain this", "concept", "breakdown"]
        case .findActionItems: ["action items", "action points", "todos", "tasks", "next steps"]
        case .convertTypeScript: ["typescript", "ts", "interface", "type", "json to ts"]
        case .slackReply: ["slack", "slack reply", "reply slack"]
        case .emailReply: ["email", "email reply", "reply email"]
        case .summarizeYouTube: ["youtube", "video summary", "summarize video", "yt transcript", "video transcript"]
        default: []
        }
    }

    /// Suggested, highest first, until the user's own habits fill the section.
    var suggestionPriority: Int? {
        switch self {
        case .clipboardHistory: 80
        case .searchFiles: 70
        case .mySchedule: 60
        case .searchEmoji: 50
        case .focusTimer: 45
        case .createQuicklink, .createSnippet: 30
        default: nil
        }
    }

    /// Query-driven: the typed text is their input, so they are built where offered, never listed.
    var isQueryDriven: Bool {
        self == .openInBrowser || self == .runShellCommand
    }

    /// Whether this command accepts trailing search arguments when typed in the root search field.
    var acceptsArguments: Bool {
        switch self {
        case .searchFiles, .searchMenuItems, .switchWindows, .define, .quickAI,
            .searchSnippets, .searchQuicklinks, .searchCustomCommands,
            .searchEmoji, .runShellCommand, .searchNotes:
            return true
        default:
            return false
        }
    }

    /// A chord carries no query, and none should be able to terminate the app outright.
    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}
