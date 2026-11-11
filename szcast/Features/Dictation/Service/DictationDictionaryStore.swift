import Foundation
import OSLog

@MainActor
@Observable
final class DictationDictionaryStore {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationDictionary")
    private let fileURL: URL

    private(set) var words: [CustomWord] = []
    var enabledPacks: Set<VocabularyPackType> = [.tech, .brands]
    var selfLearningEnabled: Bool = true

    // Vocabulary packs storage: pack -> (canonical -> [aliases])
    private var packTerms: [VocabularyPackType: [String: [String]]] = [:]

    init(
        fileURL: URL = AppPaths.applicationSupport().appending(path: "dictation-words.json")
    ) {
        self.fileURL = fileURL
        loadPacks()
        loadWords()
    }

    // MARK: - Word Management

    func addWord(canonical: String, aliases: [String] = [], category: String = "general", isAutoLearned: Bool = false) {
        let trimmed = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = words.firstIndex(where: { $0.canonical.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            // Merge aliases
            var existing = words[index]
            var set = Set(existing.aliases.map { $0.lowercased() })
            for alias in aliases {
                let clean = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty && !set.contains(clean.lowercased()) {
                    existing.aliases.append(clean)
                    set.insert(clean.lowercased())
                }
            }
            words[index] = existing
        } else {
            let cleanAliases = aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let newWord = CustomWord(canonical: trimmed, aliases: cleanAliases, category: category, isAutoLearned: isAutoLearned)
            words.insert(newWord, at: 0)
        }
        save()
    }

    func removeWord(id: UUID) {
        words.removeAll { $0.id == id }
        save()
    }

    func clearAutoLearned() {
        words.removeAll { $0.isAutoLearned }
        save()
    }

    // MARK: - Self-Learning Dictionary

    func learnCorrection(original: String, corrected: String) {
        guard selfLearningEnabled else { return }
        let origClean = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrClean = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !origClean.isEmpty, !corrClean.isEmpty, origClean.caseInsensitiveCompare(corrClean) != .orderedSame else { return }
        addWord(canonical: corrClean, aliases: [origClean], category: "learned", isAutoLearned: true)
    }

    // MARK: - Word Replacement / Post-Processing

    func applyDictionaryAndPacks(_ text: String) -> String {
        var result = text

        // 1. Apply user custom words (highest priority)
        for word in words {
            for alias in word.aliases {
                guard !alias.isEmpty else { continue }
                let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: alias) + #"\b"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let range = NSRange(result.startIndex..<result.endIndex, in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: word.canonical)
                }
            }
        }

        // 2. Apply active vocabulary packs
        for pack in enabledPacks {
            guard let dict = packTerms[pack] else { continue }
            for (canonical, aliases) in dict {
                for alias in aliases {
                    guard !alias.isEmpty else { continue }
                    let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: alias) + #"\b"#
                    if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                        let range = NSRange(result.startIndex..<result.endIndex, in: result)
                        result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: canonical)
                    }
                }
            }
        }

        return result
    }

    // MARK: - Import & Export

    func importFromText(_ content: String) -> Int {
        var count = 0
        // Check if JSON
        if let data = content.data(using: .utf8) {
            if let decoded = try? JSONDecoder().decode([CustomWord].self, from: data) {
                for word in decoded {
                    addWord(canonical: word.canonical, aliases: word.aliases, category: word.category)
                    count += 1
                }
                return count
            }
            // EnviousWispr wrapper format { "words": [...] }
            struct EnviousWisprWordsFile: Decodable {
                struct RawWord: Decodable {
                    let canonical: String
                    let aliases: [String]?
                    let category: String?
                }
                let words: [RawWord]
            }
            if let wrapper = try? JSONDecoder().decode(EnviousWisprWordsFile.self, from: data) {
                for w in wrapper.words {
                    addWord(canonical: w.canonical, aliases: w.aliases ?? [], category: w.category ?? "general")
                    count += 1
                }
                return count
            }
        }

        // Plain text list: one per line, optional "canonical -> alias1, alias2"
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if trimmed.contains("->") {
                let parts = trimmed.components(separatedBy: "->")
                let canonical = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let aliases = parts.count > 1 ? parts[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } : []
                addWord(canonical: canonical, aliases: aliases)
                count += 1
            } else if trimmed.contains(":") {
                let parts = trimmed.components(separatedBy: ":")
                let canonical = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let aliases = parts.count > 1 ? parts[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } : []
                addWord(canonical: canonical, aliases: aliases)
                count += 1
            } else {
                addWord(canonical: trimmed)
                count += 1
            }
        }
        return count
    }

    func importFromFile(at url: URL) throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)
        return importFromText(content)
    }

    func exportToJSON(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(words)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Persistence

    private func loadWords() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                words = try JSONDecoder().decode([CustomWord].self, from: data)
                return
            } catch {
                Self.logger.error("Failed to load custom words: \(error.localizedDescription)")
            }
        }

        // Seed from EnviousWispr custom-words.json if available
        let enviousWisprURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/EnviousWispr/custom-words.json")
        if FileManager.default.fileExists(atPath: enviousWisprURL.path),
           let content = try? String(contentsOf: enviousWisprURL, encoding: .utf8) {
            _ = importFromText(content)
        }
    }

    private func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(words)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save custom words: \(error.localizedDescription)")
        }
    }

    // MARK: - Pack Data Loader

    private func loadPacks() {
        // Read bundled pack JSONs from EnviousWispr directory if available or fallback
        let packsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/EnviousWispr/Resources/Packs")

        for pack in VocabularyPackType.allCases {
            var loaded = false
            let path = packsDir.appendingPathComponent("\(pack.rawValue).json")
            if FileManager.default.fileExists(atPath: path.path),
               let data = try? Data(contentsOf: path),
               let dict = try? JSONDecoder().decode([String: [String]].self, from: data) {
                packTerms[pack] = dict
                loaded = true
            }

            if !loaded {
                // Built-in starter fixes for each domain
                switch pack {
                case .tech:
                    packTerms[.tech] = [
                        "AngularJS": ["angularge", "ingiolarge", "ingiolarts"],
                        "async": ["esync", "isinc", "isync", "osinc"],
                        "autoscaling": ["autosculum", "autoskalong"],
                        "Bazel": ["basel", "bayzel"],
                        "Blazor": ["blazer", "blazor"],
                        "PostgreSQL": ["postgres queue l", "post gres q l"],
                        "Kubernetes": ["coobernetties", "coober netties"],
                        "GraphQL": ["graph q l", "graph queue l"],
                        "DevOps": ["dev ops", "dev-ops"],
                        "Xcode": ["ex code", "x code"]
                    ]
                case .medical:
                    packTerms[.medical] = [
                        "acetaminophen": ["acidaminophan", "acidaminophen"],
                        "amoxicillin": ["amaxicylin", "amaxisillin"],
                        "Celexa": ["celex", "selexa"],
                        "Fosamax": ["fosemax", "phosamax"],
                        "Humira": ["humera", "hewmera"],
                        "ibuprofen": ["eyebuprofen", "ibiprofen"]
                    ]
                case .legal:
                    packTerms[.legal] = [
                        "FERPA": ["furpa", "ferpah"],
                        "NLRB": ["nl rb", "n l r b"],
                        "accord": ["archord", "eccord"],
                        "appellate": ["epilati", "ipolate"],
                        "affidavit": ["afadavit", "affadavit"]
                    ]
                case .brands:
                    packTerms[.brands] = [
                        "adidas": ["addides", "adidos"],
                        "Adyen": ["adeyan", "adiane", "adyne"],
                        "Aetna": ["ayatna", "eatner", "oatna"],
                        "ASUS": ["asus", "eissus", "ay-soos"],
                        "Raycast": ["ray cast", "recast"],
                        "szcast": ["sz cast", "s z cast", "tinycast"]
                    ]
                case .names:
                    packTerms[.names] = [
                        "Acosta": ["acosto", "acusti", "ecosta"],
                        "Adeline": ["edline", "odline"],
                        "Aguirre": ["aguary", "agwara", "aquari"],
                        "Saurav": ["sourab", "sourav", "saurabh"]
                    ]
                }
            }
        }
    }
}
