import Foundation

struct FinderFolderDestination: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case pinned = "Pinned"
        case recent = "Recent"
        case search = "Search"
    }

    let url: URL
    let kind: Kind

    var id: String { url.path }

    var name: String {
        let last = url.lastPathComponent
        return last.isEmpty ? url.path : last
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
