import Foundation

/// This channel's own link scheme: `szcast`, or `szcast-dev` for Debug. Set in project.yml.
enum AppURLScheme {
    static let current: String = {
        guard let scheme = Bundle.main.object(forInfoDictionaryKey: "SzcastURLScheme") as? String
        else { preconditionFailure("Info.plist must name SzcastURLScheme") }
        return scheme
    }()
}
