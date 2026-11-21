import Foundation

enum EmojiPrimaryAction: String, CaseIterable, Identifiable, Sendable {
    case paste = "paste"
    case copy = "copy"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste: return String(localized: "Paste to Active App")
        case .copy: return String(localized: "Copy to Clipboard")
        }
    }

    var subtitle: String {
        switch self {
        case .paste: return String(localized: "Pressing ⏎ pastes directly; ⌘↵ copies to clipboard.")
        case .copy: return String(localized: "Pressing ⏎ copies to clipboard; ⌘↵ pastes directly.")
        }
    }
}
