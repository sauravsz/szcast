import Foundation

/// One button; role decides its colour, severity living separately in `DialogTone`.
struct DialogAction {
    enum Role {
        case standard
        case destructive
        case cancel
    }

    let title: String
    var role: Role = .standard
}

/// How serious a dialog is; it tints the glyph but never picks one. See docs/ui.md.
enum DialogTone: Sendable {
    case neutral
    case success
    case danger
}

struct DialogRequest {
    let title: String
    var message: String?
    /// Nil where the title already names the subject and a glyph would repeat it.
    let symbol: String?
    var tone: DialogTone = .neutral
    var actions: [DialogAction]
    /// The button ↵ fires, normally the primary action.
    var defaultIndex: Int
    /// Resolved when the dialog goes without a choice: Esc, or losing key status.
    var cancelIndex: Int
    /// The caller reads the result back out of the state object it passed in.
    var accessory: DialogAccessory?
}

/// A dialog carries at most one control, so the cases are exclusive by construction.
enum DialogAccessory {
    case volume(VolumeState)
    case snippetArguments(SnippetArgumentsState)
    case clipboardText(ClipboardEditState)
    case aliasInput(AliasInputState)
    case hotKeyRecord(HotKeyRecordState)
    case emojiKeywords(EmojiKeywordInputState)
    case snippetFolderConfig(SnippetFolderConfigState)

    /// Whether ←/→/↑/↓ belong to the control rather than to whatever has focus inside it.
    var claimsArrowKeys: Bool {
        if case .volume = self { return true }
        return false
    }

    /// Whether ⇥ walks the accessory's own fields rather than AppKit's key-view loop.
    var claimsTabKey: Bool {
        if case .snippetArguments = self { return true }
        return false
    }

    /// Whether ↵ belongs to a multi-line field, which leaves ⌘↵ to confirm the dialog.
    var acceptsLineBreaks: Bool {
        if case .clipboardText = self { return true }
        return false
    }
}

@MainActor
@Observable
final class AliasInputState {
    var text: String
    let placeholder: String
    let entryName: String

    init(initialText: String = "", placeholder: String = "", entryName: String = "") {
        self.text = initialText
        self.placeholder = placeholder
        self.entryName = entryName
    }
}

@MainActor
@Observable
final class HotKeyRecordState {
    let entry: AppEntry
    let action: HotKeyAction
    let initialBinding: HotKeyBinding?

    init(entry: AppEntry, action: HotKeyAction, initialBinding: HotKeyBinding?) {
        self.entry = entry
        self.action = action
        self.initialBinding = initialBinding
    }
}

@MainActor
@Observable
final class EmojiKeywordInputState {
    var text: String
    let placeholder: String
    let emojiName: String
    let glyph: String

    init(glyph: String, emojiName: String, initialKeywords: [String] = [], placeholder: String = "e.g. smile, happy, party") {
        self.glyph = glyph
        self.emojiName = emojiName
        self.text = initialKeywords.joined(separator: ", ")
        self.placeholder = placeholder
    }
}
