import Foundation

struct CustomWord: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var canonical: String
    var aliases: [String]
    var category: String
    var isAutoLearned: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        canonical: String,
        aliases: [String] = [],
        category: String = "general",
        isAutoLearned: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.canonical = canonical
        self.aliases = aliases
        self.category = category
        self.isAutoLearned = isAutoLearned
        self.createdAt = createdAt
    }
}
