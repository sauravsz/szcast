import Foundation

struct DictationSnippet: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var keyword: String
    var expansion: String

    init(id: UUID = UUID(), keyword: String, expansion: String) {
        self.id = id
        self.keyword = keyword
        self.expansion = expansion
    }
}
