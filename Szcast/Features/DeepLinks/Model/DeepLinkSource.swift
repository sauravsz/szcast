import Foundation

/// Where a link came from. One Szcast opened itself, from a quicklink, was chosen here.
enum DeepLinkSource: Sendable {
    case outside
    case szcast

    /// A quicklink reaching a quicklink could reach itself, and that loop never unwinds.
    func mayRun(_ action: HotKeyAction) -> Bool {
        guard self == .szcast, case .quicklink = action else { return true }
        return false
    }
}
