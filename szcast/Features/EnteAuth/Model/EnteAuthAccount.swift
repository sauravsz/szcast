import Foundation

enum TOTPAlgorithm: String, Codable, Sendable, CaseIterable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

struct EnteAuthAccount: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var issuer: String
    var username: String
    var secret: String
    var algorithm: TOTPAlgorithm
    var digits: Int
    var period: Int
    var tags: [String]
    var notes: String?
    var useCount: Int
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        issuer: String,
        username: String = "",
        secret: String,
        algorithm: TOTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        tags: [String] = [],
        notes: String? = nil,
        useCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.issuer = issuer
        self.username = username
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits <= 0 ? 6 : digits
        self.period = period <= 0 ? 30 : period
        self.tags = tags
        self.notes = notes
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }

    var displayTitle: String {
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return issuer.isEmpty ? "Account" : issuer
        }
        return issuer.isEmpty ? username : "\(issuer) (\(username))"
    }
}
