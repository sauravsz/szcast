import Foundation

struct DictationHistoryItem: Codable, Identifiable, Sendable {
    var id: UUID
    var timestamp: Date
    var text: String
    var rawText: String
    var duration: TimeInterval
    var wordCount: Int
    var appName: String?
    var appBundleID: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        rawText: String = "",
        duration: TimeInterval = 0,
        appName: String? = nil,
        appBundleID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.rawText = rawText.isEmpty ? text : rawText
        self.duration = duration
        self.wordCount = text.split(whereSeparator: \.isWhitespace).count
        self.appName = appName
        self.appBundleID = appBundleID
    }
}
