import Foundation

enum DictationMode: String, CaseIterable, Identifiable, Sendable {
    case pushToTalk
    case toggle

    var id: Self { self }
    var title: String {
        self == .pushToTalk
            ? String(localized: "Hold to talk (double-tap for hands-free)")
            : String(localized: "Press to start or stop")
    }
}

enum DictationPillPosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case bottomCenter = "bottomCenter"
    case topNotch = "topNotch"
    case topRight = "topRight"
    case nearCaret = "nearCaret"

    var id: Self { self }

    var title: String {
        switch self {
        case .bottomCenter: return String(localized: "Bottom Center")
        case .topNotch: return String(localized: "Top Notch / Dynamic Bar")
        case .topRight: return String(localized: "Top Right Corner")
        case .nearCaret: return String(localized: "Near Text Caret")
        }
    }
}
