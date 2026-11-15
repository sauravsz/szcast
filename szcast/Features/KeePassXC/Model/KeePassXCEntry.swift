import Foundation

struct KeePassXCEntry: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    var title: String
    var username: String
    var password: String
    var url: String
    var notes: String
    var uuid: String?
    var group: String?

    init(
        path: String,
        title: String = "",
        username: String = "",
        password: String = "",
        url: String = "",
        notes: String = "",
        uuid: String? = nil,
        group: String? = nil
    ) {
        self.path = path
        self.title = title.isEmpty ? (path.components(separatedBy: "/").last ?? path) : title
        self.username = username
        self.password = password
        self.url = url
        self.notes = notes
        self.uuid = uuid
        self.group = group
    }
}
