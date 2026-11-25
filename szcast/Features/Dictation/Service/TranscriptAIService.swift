import Foundation

/// Sectioned LLM cleanup, multi-chunk meeting summarization, and transcript Q&A.
enum TranscriptAIService {
    struct StructuredNotes: Sendable {
        var title: String
        var summary: String
        var actionItems: [String]
        var decisions: [String]
    }

    static func splitIntoWordChunks(_ text: String, maxWords: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > maxWords else { return [trimmed] }

        var chunks = [String]()
        var bucket = [String]()
        for word in words {
            bucket.append(word)
            let atSentenceEnd = word.hasSuffix(".") || word.hasSuffix("?") || word.hasSuffix("!")
            if bucket.count >= maxWords || (atSentenceEnd && bucket.count >= Int(Double(maxWords) * 0.72)) {
                chunks.append(bucket.joined(separator: " "))
                bucket.removeAll(keepingCapacity: true)
            }
        }
        if !bucket.isEmpty { chunks.append(bucket.joined(separator: " ")) }
        return chunks
    }

    static func polishLongTranscript(
        _ text: String,
        provider: DictationPolishProvider,
        s1Settings: DictationS1Settings,
        groqAPIKey: String,
        groqModel: String,
        polisher: DictationS1Polisher,
        groq: GroqPolishService
    ) async -> String {
        let wordLimit = provider == .groq ? 1_600 : 650
        let chunks = splitIntoWordChunks(text, maxWords: wordLimit)
        guard !chunks.isEmpty else { return text }

        var cleaned = [String]()
        cleaned.reserveCapacity(chunks.count)
        for chunk in chunks {
            do {
                let result: String
                switch provider {
                case .localS1:
                    result = await polisher.polish(chunk, settings: s1Settings)
                case .groq:
                    result = try await groq.polish(
                        chunk, apiKey: groqAPIKey, settings: s1Settings, model: groqModel)
                }
                cleaned.append(result)
            } catch {
                cleaned.append(chunk)
            }
        }
        return cleaned.joined(separator: "\n\n")
    }

    static func generateStructuredNotes(
        from record: TranscriptRecord,
        provider: DictationPolishProvider,
        groqAPIKey: String,
        groqModel: String,
        polisher: DictationS1Polisher,
        groq: GroqPolishService
    ) async -> StructuredNotes? {
        let sourceText = TranscriptExporter.renderPlainText(record)
        let chunks = splitIntoWordChunks(sourceText, maxWords: provider == .groq ? 2_200 : 750)
        guard !chunks.isEmpty else { return nil }

        let notesInstruction = """
            Extract concise, factual meeting or audio notes from this transcript. Return strictly in this format:
            TITLE: <short 3-8 word title>
            SUMMARY:
            <1 concise paragraph>
            ACTION ITEMS:
            - <item or None>
            DECISIONS:
            - <decision or None>
            """

        var partials = [String]()
        for chunk in chunks {
            let output = await runTransform(
                text: chunk,
                instruction: chunks.count > 1 ? "Summarize key facts, action items, and decisions:\n" + notesInstruction : notesInstruction,
                provider: provider,
                groqAPIKey: groqAPIKey,
                groqModel: groqModel,
                polisher: polisher,
                groq: groq
            )
            if let output, !output.isEmpty { partials.append(output) }
        }
        guard !partials.isEmpty else { return nil }

        let combinedResponse: String
        if partials.count == 1 {
            combinedResponse = partials[0]
        } else {
            combinedResponse = await runTransform(
                text: partials.joined(separator: "\n\n---\n\n"),
                instruction: "Merge these partial notes into one unified note using the exact format:\n" + notesInstruction,
                provider: provider,
                groqAPIKey: groqAPIKey,
                groqModel: groqModel,
                polisher: polisher,
                groq: groq
            ) ?? partials.joined(separator: "\n\n")
        }

        return parseStructuredNotes(combinedResponse, fallbackTitle: record.title)
    }

    static func askQuestion(
        _ question: String,
        about record: TranscriptRecord,
        provider: DictationPolishProvider,
        groqAPIKey: String,
        groqModel: String,
        polisher: DictationS1Polisher,
        groq: GroqPolishService
    ) async throws -> String {
        let contextText = TranscriptExporter.renderPlainText(record)
        let chunks = splitIntoWordChunks(contextText, maxWords: provider == .groq ? 2_400 : 850)
        let selectedContext = selectRelevantChunks(chunks, query: question, maxChunks: provider == .groq ? 3 : 2)
            .joined(separator: "\n\n")
        let instruction = """
            Answer the user's question accurately using ONLY the provided transcript context.
            Include speaker names and [MM:SS] timestamps when citing details.
            Question: \(question)
            """
        guard let answer = await runTransform(
            text: selectedContext,
            instruction: instruction,
            provider: provider,
            groqAPIKey: groqAPIKey,
            groqModel: groqModel,
            polisher: polisher,
            groq: groq
        ), !answer.isEmpty else {
            throw CocoaError(.fileReadUnknown)
        }
        return answer
    }

    private static func selectRelevantChunks(_ chunks: [String], query: String, maxChunks: Int) -> [String] {
        guard chunks.count > maxChunks else { return chunks }
        let terms = Set(
            query.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )
        guard !terms.isEmpty else { return Array(chunks.prefix(maxChunks)) }
        let ranked = chunks.enumerated().sorted { lhs, rhs in
            let lScore = terms.reduce(0) { $0 + (lhs.element.lowercased().contains($1) ? 1 : 0) }
            let rScore = terms.reduce(0) { $0 + (rhs.element.lowercased().contains($1) ? 1 : 0) }
            if lScore == rScore { return lhs.offset < rhs.offset }
            return lScore > rScore
        }
        return ranked.prefix(maxChunks).sorted { $0.offset < $1.offset }.map(\.element)
    }

    private static func runTransform(
        text: String,
        instruction: String,
        provider: DictationPolishProvider,
        groqAPIKey: String,
        groqModel: String,
        polisher: DictationS1Polisher,
        groq: GroqPolishService
    ) async -> String? {
        switch provider {
        case .localS1:
            return await polisher.transform(text: text, instruction: instruction, settings: .default)
        case .groq:
            guard !groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return try? await groq.transform(
                text: text, instruction: instruction, apiKey: groqAPIKey, model: groqModel)
        }
    }

    static func parseStructuredNotes(_ raw: String, fallbackTitle: String) -> StructuredNotes {
        var title = fallbackTitle
        var summaryLines = [String]()
        var actions = [String]()
        var decisions = [String]()
        enum Section { case none, summary, actions, decisions }
        var section: Section = .none

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if upper.hasPrefix("TITLE:") {
                let candidate = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty { title = candidate }
                section = .none
            } else if upper.hasPrefix("SUMMARY:") {
                let rest = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { summaryLines.append(rest) }
                section = .summary
            } else if upper.hasPrefix("ACTION ITEMS:") {
                section = .actions
            } else if upper.hasPrefix("DECISIONS:") {
                section = .decisions
            } else if !trimmed.isEmpty {
                let bullet = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-*• "))
                switch section {
                case .none, .summary:
                    summaryLines.append(trimmed)
                case .actions:
                    if bullet.lowercased() != "none", !bullet.isEmpty { actions.append(bullet) }
                case .decisions:
                    if bullet.lowercased() != "none", !bullet.isEmpty { decisions.append(bullet) }
                }
            }
        }

        return StructuredNotes(
            title: title,
            summary: summaryLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            actionItems: actions,
            decisions: decisions
        )
    }
}
