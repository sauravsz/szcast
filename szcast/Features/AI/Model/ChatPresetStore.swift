import Foundation

@MainActor
@Observable
final class ChatPresetStore {
    private(set) var presets: [ChatPreset] = []
    /// False when the file wouldn't read; every mutation then refuses rather than pretends.
    private(set) var isAvailable = true

    private let fileURL: URL
    private let isDefaultLocation: Bool

    init(directory: URL? = nil) {
        self.isDefaultLocation = (directory == nil)
        fileURL = (directory ?? Self.defaultDirectory).appendingPathComponent("chat-presets.json")
    }

    private static var defaultDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sauravsz.szcast"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    /// Runs each time AI is switched on, so it starts over rather than keep an old refusal.
    func load() {
        presets = []
        isAvailable = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            if isDefaultLocation {
                presets = Self.defaultPresets
                try? commit(presets)
            }
            return
        }
        // A file that exists but won't read is authored data: report, never write over it.
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([ChatPreset].self, from: data)
        else {
            isAvailable = false
            return
        }
        var ids = Set<UUID>()
        presets = decoded.compactMap { try? Self.validated($0) }
            .filter { ids.insert($0.id).inserted }
            .sorted(by: ChatPreset.precedes)
    }

    static let defaultPresets: [ChatPreset] = [
        ChatPreset(
            name: "Software Engineer",
            iconSymbol: "chevron.left.forwardslash.chevron.right",
            instructions: "You are an expert senior software engineer and systems architect. Provide idiomatic, clean, secure, performant, and production-ready code with concise, technical reasoning."
        ),
        ChatPreset(
            name: "Marketing Copywriter",
            iconSymbol: "megaphone",
            instructions: "You are a master direct-response copywriter. Craft compelling, conversion-focused headlines, value propositions, and calls to action that captivate target audiences."
        ),
        ChatPreset(
            name: "UX Copywriter",
            iconSymbol: "hand.tap",
            instructions: "You are a specialized UX writer and product copy expert. Write ultra-clear, concise, helpful interface copy, microcopy, modals, empty states, and user prompts."
        ),
        ChatPreset(
            name: "Blogpost Writer",
            iconSymbol: "doc.richtext",
            instructions: "You are an engaging long-form writer and essayist. Structure and write insightful, well-researched, narrative-driven articles with memorable takeaways."
        ),
        ChatPreset(
            name: "YouTube Script Creator",
            iconSymbol: "play.tv",
            instructions: "You are an expert video producer and YouTube creator. Create high-retention video scripts featuring powerful hooks, seamless section transitions, and strong viewer engagement."
        ),
        ChatPreset(
            name: "Career Coach",
            iconSymbol: "briefcase",
            instructions: "You are an executive career advisor. Review resumes, help formulate interview strategies, guide salary negotiations, and craft compelling professional narratives."
        ),
        ChatPreset(
            name: "Dad Joke",
            iconSymbol: "face.smiling",
            instructions: "You are the quintessential master of groan-worthy, clean, wholesome dad jokes and puns. Deliver the punchline cleanly without explaining it."
        ),
        ChatPreset(
            name: "Slack Reply",
            iconSymbol: "bubble.left.and.bubble.right",
            instructions: "Draft concise, helpful, and professional yet casual responses tailored for Slack or workplace team chat."
        ),
        ChatPreset(
            name: "Email Reply",
            iconSymbol: "envelope",
            instructions: "Craft professional email responses with proper business etiquette, addressing all questions and outlining clear next steps."
        ),
    ]

    func preset(id: UUID) -> ChatPreset? {
        presets.first { $0.id == id }
    }

    @discardableResult
    func add(_ draft: ChatPreset) throws(ChatPresetError) -> ChatPreset {
        let value = try Self.validated(draft)
        try commit(presets + [value])
        return value
    }

    func update(_ draft: ChatPreset) throws(ChatPresetError) {
        guard let index = presets.firstIndex(where: { $0.id == draft.id }) else { return }
        var updated = presets
        updated[index] = try Self.validated(draft)
        try commit(updated)
    }

    @discardableResult
    func remove(id: UUID) throws(ChatPresetError) -> ChatPreset? {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return nil }
        var updated = presets
        let removed = updated.remove(at: index)
        try commit(updated)
        return removed
    }

    private static func validated(_ draft: ChatPreset) throws(ChatPresetError) -> ChatPreset {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol = draft.iconSymbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        value.iconSymbol = symbol.isEmpty ? nil : symbol
        value.instructions = draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { throw .emptyName }
        guard !value.name.contains("\0") else { throw .invalidCharacter }
        guard !value.instructions.isEmpty else { throw .emptyInstructions }
        return value
    }

    /// Persisted before the list moves, so a save the reader was told landed is on disk.
    private func commit(_ updated: [ChatPreset]) throws(ChatPresetError) {
        guard isAvailable else { throw .storageUnavailable }
        let ordered = updated.sorted(by: ChatPreset.precedes)
        guard ordered != presets else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(ordered),
            (try? data.write(to: fileURL, options: .atomic)) != nil
        else { throw .storageUnavailable }
        presets = ordered
    }
}
