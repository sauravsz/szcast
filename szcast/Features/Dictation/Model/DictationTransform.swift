import Foundation

public struct DictationTransform: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var systemPrompt: String
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        systemPrompt: String,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.systemPrompt = systemPrompt
        self.isBuiltIn = isBuiltIn
    }

    public static let standardClean = DictationTransform(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Clean & Polish",
        summary: "Default transcription cleaning with filler removal and smart punctuation.",
        systemPrompt: "Clean dictated speech for direct paste. Output only the cleaned text. Delete disfluencies, filler words (um, uh, like), and repetitions. Resolve speech repairs. Apply standard capitalization, spelling, and sentence boundaries. Keep everything else verbatim.",
        isBuiltIn: true
    )

    public static let bulletPoints = DictationTransform(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Bullet Points & Actions",
        summary: "Transforms rambling spoken thoughts into structured bulleted items.",
        systemPrompt: "Transform the spoken input into a structured markdown list of bullet points and clear action items. Group related points cleanly. Output only the markdown bullet list with no introductory or concluding chat.",
        isBuiltIn: true
    )

    public static let executiveSummary = DictationTransform(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Executive Summary",
        summary: "Condenses spoken ideas into a crisp 2-3 sentence executive brief.",
        systemPrompt: "Condense the input transcript into an executive summary of 2 to 3 sentences. Highlight the core message, decisions, and immediate next steps. Output only the summary prose without conversational padding.",
        isBuiltIn: true
    )

    public static let professionalEmail = DictationTransform(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Professional Email",
        summary: "Formats spoken thoughts into a ready-to-send professional email.",
        systemPrompt: "Format the dictated thoughts into a polite, structured professional email. Include an appropriate greeting, concise body paragraphs, and professional sign-off. Output only the email text.",
        isBuiltIn: true
    )

    public static let codeRefinement = DictationTransform(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "Technical & Code",
        summary: "Formats technical speech with code identifiers, backticks, and camelCase.",
        systemPrompt: "Format the technical transcription cleanly. Preserve code identifiers, variable names, snake_case, camelCase, filenames, and markdown backticks. Do not alter technical terms. Output only the formatted technical text.",
        isBuiltIn: true
    )

    public static let promptEngineer = DictationTransform(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        name: "Prompt Engineer",
        summary: "Structures verbal brain-dumps into a rigorous, production-grade LLM prompt.",
        systemPrompt: "You are an expert prompt engineer. Take the dictated thoughts, goals, and constraints and structure them into a high-performance LLM prompt with the following sections:\n\n**Role & Stance**\n**Objective / Task**\n**Context & Background**\n**Constraints & Rules**\n**Format & Output Instructions**\n\nOutput only the engineered markdown prompt without introductory chatter or conclusion.",
        isBuiltIn: true
    )

    public static let defaultTransforms: [DictationTransform] = [
        .standardClean,
        .bulletPoints,
        .executiveSummary,
        .professionalEmail,
        .codeRefinement,
        .promptEngineer
    ]
}

@MainActor
public final class DictationTransformStore {
    private let fileURL: URL
    public private(set) var customTransforms: [DictationTransform] = []

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("szcast", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("dictation-transforms.json")
        }
        load()
    }

    public var allTransforms: [DictationTransform] {
        DictationTransform.defaultTransforms + customTransforms
    }

    public func transform(with id: UUID) -> DictationTransform? {
        allTransforms.first { $0.id == id }
    }

    public func transform(with idString: String?) -> DictationTransform? {
        guard let idString, let uuid = UUID(uuidString: idString) else { return nil }
        return transform(with: uuid)
    }

    public func add(_ transform: DictationTransform) {
        var copy = transform
        copy.isBuiltIn = false
        customTransforms.removeAll { $0.id == copy.id }
        customTransforms.append(copy)
        save()
    }

    public func remove(id: UUID) {
        customTransforms.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([DictationTransform].self, from: data) {
            self.customTransforms = decoded
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(customTransforms) {
            try? encoded.write(to: fileURL, options: .atomic)
        }
    }
}
