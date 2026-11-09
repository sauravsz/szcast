import Foundation

/// The fork ships no signed release stream yet, so no build updates itself. Add a
/// channel here — and a real feed — if a release pipeline lands later.
enum ReleaseChannel: Sendable {
    case stable
    case beta
    /// A local build. It has no release stream, and never updates itself.
    case development

    init(bundleID: String?) {
        switch bundleID {
        case "": self = .development
        case _: self = .development
        }
    }

    var updatesItself: Bool { self != .development }

    /// Beta ships as a GitHub prerelease and stable does not; neither ever sees the other's.
    func accepts(prerelease: Bool) -> Bool {
        switch self {
        case .stable: return !prerelease
        case .beta: return prerelease
        case .development: return false
        }
    }
}
