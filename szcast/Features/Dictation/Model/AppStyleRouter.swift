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

    static func category(
        for bundleID: String?,
        windowTitle: String? = nil,
        documentURL: String? = nil
    ) -> AppCategory {
        guard let bundleID = bundleID?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !bundleID.isEmpty else {
            return categoryFromWindowContext(windowTitle: windowTitle, documentURL: documentURL)
        }
        // Strict redaction: never inspect title/URL for credential or 2FA apps.
        if bundleID.contains("keepass") || bundleID.contains("ente") || bundleID.contains("1password")
            || bundleID.contains("bitwarden") || bundleID.contains("keychain") {
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

        return categoryFromWindowContext(windowTitle: windowTitle, documentURL: documentURL)
    }

    private static func categoryFromWindowContext(windowTitle: String?, documentURL: String?) -> AppCategory {
        let url = (documentURL ?? "").lowercased()
        let title = (windowTitle ?? "").lowercased()
        let combined = url + " " + title
        guard !combined.trimmingCharacters(in: .whitespaces).isEmpty else { return .general }

        if url.contains("mail.google.com") || url.contains("outlook.live.com") || url.contains("outlook.office.com")
            || url.contains("fastmail.com") || url.contains("proton.me") || title.contains("gmail") || title.hasSuffix(" - mail") {
            return .email
        }
        if url.contains("github.com") || url.contains("gitlab.com") || url.contains("bitbucket.org")
            || url.contains("linear.app") || url.contains("stackoverflow.com") || url.contains("codepen.io")
            || title.contains("pull request") || title.contains("github") {
            return .code
        }
        if url.contains("app.slack.com") || url.contains("slack.com") || url.contains("discord.com")
            || url.contains("teams.microsoft.com") || url.contains("meet.google.com") {
            return .workMessaging
        }
        if url.contains("web.whatsapp.com") || url.contains("web.telegram.org") || url.contains("messages.google.com")
            || url.contains("messenger.com") {
            return .personalMessaging
        }
        if url.contains("notion.so") || url.contains("docs.google.com") || url.contains("obsidian.md")
            || url.contains("roamresearch.com") || url.contains("coda.io") || title.contains("notion") || title.contains("google docs") {
            return .notes
        }
        return .general
    }

    /// Resolves S1 prompt settings according to the frontmost application category and browser context.
    static func resolvedS1Settings(
        base: DictationS1Settings,
        bundleID: String?,
        windowTitle: String? = nil,
        documentURL: String? = nil
    ) -> DictationS1Settings {
        let cat = category(for: bundleID, windowTitle: windowTitle, documentURL: documentURL)
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
    /// E.g. in personal messaging & code/terminal apps, single short lines drop a stray trailing period.
    static func applyCategoryFormatting(
        _ text: String,
        bundleID: String?,
        windowTitle: String? = nil,
        documentURL: String? = nil
    ) -> String {
        let cat = category(for: bundleID, windowTitle: windowTitle, documentURL: documentURL)
        var result = text

        if cat == .personalMessaging || cat == .code {
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(".") && !trimmed.hasSuffix("...") && !trimmed.hasSuffix("…") {
                let periods = trimmed.filter { $0 == "." }.count
                let isSingleLineCode = (cat != .code) || !trimmed.contains("\n")
                if periods == 1 && isSingleLineCode {
                    result = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return result
    }
}
