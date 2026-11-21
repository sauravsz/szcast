import Foundation

enum AppCategory: String, CaseIterable, Codable, Sendable {
    case personalMessaging = "personalMessaging"
    case workMessaging = "workMessaging"
    case email = "email"
    case code = "code"
    case notes = "notes"
    case general = "general"

    var title: String {
        switch self {
        case .personalMessaging: return String(localized: "Personal Messaging")
        case .workMessaging: return String(localized: "Work Messaging")
        case .email: return String(localized: "Email")
        case .code: return String(localized: "Code & Terminal")
        case .notes: return String(localized: "Notes & Docs")
        case .general: return String(localized: "General")
        }
    }
}

enum AppStyleRouter {
    private static let personalMessagingBundleIDs: Set<String> = [
        "net.whatsapp.whatsapp",
        "net.whatsapp.whatsapp.service",
        "ru.keepcoder.telegram",
        "org.telegram.desktop",
        "com.apple.mobilesms",
        "org.whispersystems.signal-desktop",
        "com.viber.osx"
    ]

    private static let workMessagingBundleIDs: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.hnc.discord",
        "mattermost.desktop",
        "com.mattermost.desktop",
        "com.skype.skype"
    ]

    private static let emailBundleIDs: Set<String> = [
        "com.apple.mail",
        "com.mimestream.mimestream",
        "com.microsoft.outlook",
        "com.superhuman.electron",
        "com.readdle.smartemail",
        "com.readdle.smartimail",
        "com.canarymail.mac",
        "org.mozilla.thunderbird",
        "com.boxersoftware.mail"
    ]

    private static let codeBundleIDs: Set<String> = [
        "com.microsoft.vscode",
        "com.microsoft.vscodeinsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.apple.dt.xcode",
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "dev.zed.zed",
        "com.mitchellh.ghostty",
        "io.alacritty",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.panic.nova",
        "org.gnu.emacs"
    ]

    private static let notesBundleIDs: Set<String> = [
        "com.apple.notes",
        "md.obsidian",
        "notion.id",
        "com.lukilabs.lukiapp",
        "net.shinyfrog.bear",
        "com.logseq.logseq",
        "com.electron.ia-writer"
    ]

    static func category(for bundleID: String?) -> AppCategory {
        guard let bundleID = bundleID?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !bundleID.isEmpty else {
            return .general
        }

        if personalMessagingBundleIDs.contains(bundleID) { return .personalMessaging }
        if workMessagingBundleIDs.contains(bundleID) { return .workMessaging }
        if emailBundleIDs.contains(bundleID) { return .email }
        if codeBundleIDs.contains(bundleID) { return .code }
        if notesBundleIDs.contains(bundleID) { return .notes }

        // Heuristics for unknown bundle IDs
        if bundleID.contains("whatsapp") || bundleID.contains("telegram") || bundleID.contains("signal") {
            return .personalMessaging
        }
        if bundleID.contains("slack") || bundleID.contains("teams") || bundleID.contains("discord") {
            return .workMessaging
        }
        if bundleID.contains("mail") || bundleID.contains("outlook") {
            return .email
        }
        if bundleID.contains("code") || bundleID.contains("xcode") || bundleID.contains("term") || bundleID.contains("ide") {
            return .code
        }
        if bundleID.contains("note") || bundleID.contains("notion") || bundleID.contains("obsidian") {
            return .notes
        }

        return .general
    }

    /// Resolves S1 prompt settings according to the frontmost application category.
    static func resolvedS1Settings(base: DictationS1Settings, bundleID: String?) -> DictationS1Settings {
        let cat = category(for: bundleID)
        var resolved = base

        switch cat {
        case .personalMessaging:
            resolved.tone = .casual
            resolved.context = .general
            resolved.structure = .prose
        case .workMessaging:
            resolved.tone = .semiCasual
            resolved.context = .general
        case .email:
            resolved.tone = .formal
            resolved.context = .email
        case .code:
            resolved.tone = .semiFormal
            resolved.context = .general
        case .notes:
            resolved.tone = .semiFormal
        case .general:
            break
        }

        return resolved
    }

    /// Formats post-processed text specifically for the target app category.
    /// E.g. in personal messaging apps, single short messages drop trailing period.
    static func applyCategoryFormatting(_ text: String, bundleID: String?) -> String {
        let cat = category(for: bundleID)
        var result = text

        if cat == .personalMessaging {
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            // If it's a single sentence or short chat line ending in a period, drop the final period
            if trimmed.hasSuffix(".") && !trimmed.hasSuffix("...") && !trimmed.hasSuffix("…") {
                let periods = trimmed.filter { $0 == "." }.count
                if periods == 1 {
                    result = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return result
    }
}
