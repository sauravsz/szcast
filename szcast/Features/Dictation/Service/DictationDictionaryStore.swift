import Foundation
import OSLog

@MainActor
@Observable
final class DictationDictionaryStore {
    private static let logger = Logger(subsystem: "com.sauravsz.szcast", category: "DictationDictionary")
    private static let enabledPacksDefaultsKey = "dictationEnabledVocabularyPacks"
    private let fileURL: URL
    private let snippetsFileURL: URL

    private(set) var words: [CustomWord] = [] {
        didSet { cachedCustomRules = nil }
    }
    private(set) var snippets: [DictationSnippet] = [] {
        didSet { cachedSnippetRules = nil }
    }
    var enabledPacks: Set<VocabularyPackType> = [.tech, .brands] {
        didSet {
            saveEnabledPacks()
            cachedPackRules = nil
        }
    }
    var selfLearningEnabled: Bool = true

    // Vocabulary packs storage: pack -> (canonical -> [aliases])
    private var packTerms: [VocabularyPackType: [String: [String]]] = [:] {
        didSet { cachedPackRules = nil }
    }
    @ObservationIgnored private var cachedCustomRules: CompiledRuleSet?
    @ObservationIgnored private var cachedPackRules: CompiledRuleSet?
    @ObservationIgnored private var cachedSnippetRules: CompiledRuleSet?
    private static let correctionStatsDefaultsKey = "dictationCorrectionHitCounts"
    private(set) var correctionHitCounts: [String: Int] = [:]

    init(
        fileURL: URL = AppPaths.applicationSupport().appending(path: "dictation-words.json"),
        snippetsFileURL: URL = AppPaths.applicationSupport().appending(path: "dictation-snippets.json")
    ) {
        self.fileURL = fileURL
        self.snippetsFileURL = snippetsFileURL
        if let saved = UserDefaults.standard.stringArray(forKey: Self.enabledPacksDefaultsKey) {
            let loaded = saved.compactMap { VocabularyPackType(rawValue: $0) }
            self.enabledPacks = Set(loaded)
        } else {
            self.enabledPacks = [.tech, .brands]
        }
        if let stats = UserDefaults.standard.dictionary(forKey: Self.correctionStatsDefaultsKey) as? [String: Int] {
            self.correctionHitCounts = stats
        }
        loadPacks()
        loadWords()
        loadSnippets()
    }

    private func saveEnabledPacks() {
        let keys = enabledPacks.map(\.rawValue)
        UserDefaults.standard.set(keys, forKey: Self.enabledPacksDefaultsKey)
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
        let statKey = "\(origClean.lowercased())→\(corrClean)"
        correctionHitCounts[statKey, default: 0] += 1
        UserDefaults.standard.set(correctionHitCounts, forKey: Self.correctionStatsDefaultsKey)
        addWord(canonical: corrClean, aliases: [origClean], category: "learned", isAutoLearned: true)
    }

    /// Detects a single-word manual fix between pasted dictation text and post-edit text in the target field.
    static func detectEditedWordPair(original: String, edited: String) -> (original: String, corrected: String)? {
        let trimPunct = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        let origWords = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let newWords = edited.split(whereSeparator: \.isWhitespace).map(String.init)
        guard origWords.count >= 1, origWords.count <= 30, origWords.count == newWords.count else { return nil }

        var diffIndex: Int?
        for i in origWords.indices where origWords[i] != newWords[i] {
            if diffIndex != nil { return nil } // More than one word edited -> ambiguous
            diffIndex = i
        }
        guard let idx = diffIndex else { return nil }
        let oWord = origWords[idx].trimmingCharacters(in: trimPunct)
        let nWord = newWords[idx].trimmingCharacters(in: trimPunct)
        guard oWord.count >= 3, nWord.count >= 3, oWord != nWord else { return nil }
        guard oWord.rangeOfCharacter(from: .letters) != nil, nWord.rangeOfCharacter(from: .letters) != nil else {
            return nil
        }
        // Only learn likely spelling/casing corrections (close in length or shared initial) rather than unrelated synonyms.
        let sameInitial = oWord.lowercased().first == nWord.lowercased().first
        let maxDelta = max(3, oWord.count / 2)
        guard sameInitial || editDistance(oWord.lowercased(), nWord.lowercased()) <= maxDelta else {
            return nil
        }
        return (oWord, nWord)
    }

    // MARK: - Word Replacement / Post-Processing

    private struct ReplacementRule {
        let phrase: String
        let canonical: String
    }

    private struct CompiledReplacementRule {
        let regex: NSRegularExpression
        let template: String
    }

    private struct CompiledRuleSet {
        let trieRoot: HotwordTrieNode
        let maxPhraseWords: Int
        let normalizeApostrophes: Bool
        let regexFallback: [CompiledReplacementRule]
    }

    private final class HotwordTrieNode {
        var children: [String: HotwordTrieNode] = [:]
        var canonical: String?
    }

    private struct PhoneticTarget {
        let canonical: String
        let normalized: String
        let skeleton: String
        let initialGroup: Character
        let isShortAcronym: Bool
    }

    private static let connectorWords: Set<String> = [
        "a", "an", "and", "at", "by", "for", "from", "in", "into", "of", "off", "on", "or", "per",
        "the", "to", "with"
    ]

    private static let commonWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "do", "for", "from", "go", "he", "her",
        "him", "his", "how", "i", "if", "in", "into", "is", "it", "its", "me", "my", "no", "not",
        "of", "off", "on", "one", "or", "our", "out", "over", "per", "say", "she", "so", "some",
        "than", "that", "the", "them", "then", "they", "this", "to", "two", "up", "us", "use",
        "very", "was", "we", "were", "what", "when", "who", "why", "will", "with", "you", "your",
        "about", "after", "again", "against", "almost", "along", "already", "also", "always", "among",
        "another", "answer", "anyone", "anything", "around", "because", "become", "before", "begin",
        "behind", "being", "below", "between", "better", "black", "bring", "build", "business", "cannot",
        "change", "check", "child", "children", "clean", "clear", "close", "color", "could", "country",
        "course", "create", "doing", "during", "early", "either", "enough", "every", "example", "family",
        "father", "feeling", "first", "follow", "found", "friend", "getting", "given", "going", "great",
        "group", "hand", "happy", "having", "heard", "heart", "helps", "higher", "house", "however",
        "important", "including", "inside", "instead", "interest", "issues", "keep", "keeping", "known",
        "large", "later", "learn", "least", "leave", "letter", "level", "light", "likely", "little",
        "local", "longer", "looking", "making", "maybe", "meaning", "might", "minute", "moment", "money",
        "month", "morning", "mother", "moving", "music", "myself", "name", "nearly", "never", "night",
        "nothing", "number", "often", "order", "other", "others", "outside", "paper", "parts", "party",
        "people", "person", "place", "please", "point", "power", "present", "pretty", "price", "print",
        "problem", "public", "quick", "quiet", "quite", "rather", "really", "reason", "record", "return",
        "right", "running", "school", "second", "seems", "sending", "sense", "several", "should", "shown",
        "shows", "simple", "since", "single", "small", "someone", "something", "sometimes", "sorry", "sound",
        "space", "speak", "special", "start", "state", "still", "story", "study", "stuff", "system",
        "taking", "thanks", "their", "theirs", "there", "these", "thing", "things", "think", "third",
        "those", "though", "thought", "three", "through", "today", "together", "tomorrow", "tonight",
        "total", "trying", "under", "until", "using", "usually", "value", "version", "video", "voice",
        "waiting", "wanted", "water", "where", "whether", "which", "while", "white", "whole", "whose",
        "within", "without", "woman", "women", "words", "working", "works", "world", "would", "write",
        "wrong", "years", "yesterday", "young", "yours", "yourself"
    ]

    private static func compileRules(
        _ rules: [ReplacementRule],
        normalizeApostrophes: Bool
    ) -> CompiledRuleSet {
        // Build O(n) longest-match prefix trie for word phrases + regex fallback for symbol/non-word phrases.
        let sorted = rules.sorted { $0.phrase.count > $1.phrase.count }
        let root = HotwordTrieNode()
        var maxWords = 1
        var fallback: [CompiledReplacementRule] = []
        let phraseTokenRegex = try? NSRegularExpression(pattern: #"^[A-Za-z0-9'’]+(?:\s+[A-Za-z0-9'’]+)*$"#)

        for rule in sorted {
            let trimmed = rule.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if phraseTokenRegex?.firstMatch(in: trimmed, range: fullRange) != nil {
                let norm = normalizeApostrophes
                    ? trimmed.replacingOccurrences(of: "’", with: "'").lowercased()
                    : trimmed.lowercased()
                let parts = norm.split(whereSeparator: \.isWhitespace).map(String.init)
                guard !parts.isEmpty else { continue }
                maxWords = max(maxWords, parts.count)
                var node = root
                for part in parts {
                    if let existing = node.children[part] {
                        node = existing
                    } else {
                        let next = HotwordTrieNode()
                        node.children[part] = next
                        node = next
                    }
                }
                if node.canonical == nil {
                    node.canonical = rule.canonical
                }
            } else {
                let escaped = NSRegularExpression.escapedPattern(for: trimmed)
                let body = normalizeApostrophes ? escaped.replacingOccurrences(of: "'", with: "['’]") : escaped
                let pattern = #"\b"# + body + #"\b"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    fallback.append(
                        CompiledReplacementRule(
                            regex: regex,
                            template: NSRegularExpression.escapedTemplate(for: rule.canonical)
                        )
                    )
                }
            }
        }
        return CompiledRuleSet(
            trieRoot: root,
            maxPhraseWords: maxWords,
            normalizeApostrophes: normalizeApostrophes,
            regexFallback: fallback
        )
    }

    private static func applyCompiled(_ ruleSet: CompiledRuleSet, to text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text

        // Fast O(tokens * maxPhraseWords) trie scan across word boundaries.
        let tokens = wordTokens(in: result)
        if !tokens.isEmpty, !ruleSet.trieRoot.children.isEmpty {
            var replacements: [(range: NSRange, canonical: String)] = []
            var idx = 0
            while idx < tokens.count {
                var node: HotwordTrieNode? = ruleSet.trieRoot
                var bestMatch: (endIdx: Int, canonical: String)?
                var probe = idx
                while probe < tokens.count && (probe - idx) < ruleSet.maxPhraseWords {
                    let rawTok = tokens[probe].surface
                    let key = ruleSet.normalizeApostrophes
                        ? rawTok.replacingOccurrences(of: "’", with: "'").lowercased()
                        : rawTok.lowercased()
                    guard let next = node?.children[key] else { break }
                    node = next
                    if let canon = next.canonical {
                        bestMatch = (probe, canon)
                    }
                    probe += 1
                }
                if let hit = bestMatch {
                    let combined = NSUnionRange(tokens[idx].range, tokens[hit.endIdx].range)
                    replacements.append((combined, hit.canonical))
                    idx = hit.endIdx + 1
                } else {
                    idx += 1
                }
            }
            if !replacements.isEmpty {
                let mutable = NSMutableString(string: result)
                for rep in replacements.reversed() {
                    mutable.replaceCharacters(in: rep.range, with: rep.canonical)
                }
                result = mutable as String
            }
        }

        for rule in ruleSet.regexFallback {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result, options: [], range: range, withTemplate: rule.template
            )
        }
        return result
    }

    private func customRules() -> CompiledRuleSet {
        if let cachedCustomRules { return cachedCustomRules }
        var rules: [ReplacementRule] = []
        for word in words {
            let canon = word.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canon.isEmpty else { continue }
            for alias in word.aliases {
                let clean = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    rules.append(ReplacementRule(phrase: clean, canonical: canon))
                }
            }
            rules.append(ReplacementRule(phrase: canon, canonical: canon))
        }
        let compiled = Self.compileRules(rules, normalizeApostrophes: true)
        cachedCustomRules = compiled
        return compiled
    }

    private func packRules() -> CompiledRuleSet {
        if let cachedPackRules { return cachedPackRules }
        var rules: [ReplacementRule] = []
        for pack in enabledPacks {
            guard let dict = packTerms[pack] else { continue }
            for (canonical, aliases) in dict {
                let canon = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !canon.isEmpty else { continue }
                for alias in aliases {
                    let clean = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        rules.append(ReplacementRule(phrase: clean, canonical: canon))
                    }
                }
                rules.append(ReplacementRule(phrase: canon, canonical: canon))
            }
        }
        let compiled = Self.compileRules(rules, normalizeApostrophes: true)
        cachedPackRules = compiled
        return compiled
    }

    private func snippetRules() -> CompiledRuleSet {
        if let cachedSnippetRules { return cachedSnippetRules }
        let rules = snippets.compactMap { snippet -> ReplacementRule? in
            let kw = snippet.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !kw.isEmpty else { return nil }
            return ReplacementRule(phrase: kw, canonical: snippet.expansion)
        }
        let compiled = Self.compileRules(rules, normalizeApostrophes: false)
        cachedSnippetRules = compiled
        return compiled
    }

    func applyDictionaryAndPacks(_ text: String) -> String {
        var result = Self.applyCompiled(customRules(), to: text)
        result = Self.applyCompiled(packRules(), to: result)
        return applyPhoneticRecovery(to: result)
    }

    func promptVocabularyHint(for transcript: String? = nil, maxTerms: Int = 40) -> [String] {
        guard maxTerms > 0 else { return [] }
        let sortedCustom = words.sorted { !$0.isAutoLearned && $1.isAutoLearned }
        var seen = Set<String>()
        var selected: [String] = []
        var totalChars = 0

        func appendTerm(_ raw: String) -> Bool {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.lowercased()
            guard !clean.isEmpty, !seen.contains(key) else { return true }
            guard selected.count < maxTerms, totalChars + clean.count <= 450 else { return false }
            seen.insert(key)
            selected.append(clean)
            totalChars += clean.count + 2
            return true
        }

        for word in sortedCustom where !appendTerm(word.canonical) {
            return selected
        }

        if let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let transcriptLower = transcript.lowercased()
            let tokens = Self.wordTokens(in: transcript)
            let tokenSkeletons = Set(tokens.map { Self.phoneticSkeleton($0.normalized) }.filter { !$0.isEmpty })
            for pack in enabledPacks {
                guard let dict = packTerms[pack] else { continue }
                for canonical in dict.keys.sorted() {
                    let norm = Self.normalizedAlphaNumeric(canonical)
                    guard norm.count >= 4 else { continue }
                    let skeleton = Self.phoneticSkeleton(norm)
                    if transcriptLower.contains(canonical.lowercased()) || tokenSkeletons.contains(skeleton) {
                        if !appendTerm(canonical) { return selected }
                    }
                }
            }
        }
        return selected
    }

    private func phoneticTargets() -> [PhoneticTarget] {
        var targets: [PhoneticTarget] = []
        var seen = Set<String>()
        for word in words {
            let canon = word.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            let norm = Self.normalizedAlphaNumeric(canon)
            let upperAndDigitCount = canon.unicodeScalars.filter {
                CharacterSet.uppercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0)
            }.count
            let isShortAcronym = norm.count >= 2 && norm.count <= 3 && upperAndDigitCount >= 2 && !Self.commonWords.contains(norm)
            guard (norm.count >= 4 || isShortAcronym), !seen.contains(norm) else { continue }
            seen.insert(norm)
            let skeleton = Self.phoneticSkeleton(norm)
            if let initial = skeleton.first, !skeleton.isEmpty {
                targets.append(
                    PhoneticTarget(
                        canonical: canon,
                        normalized: norm,
                        skeleton: skeleton,
                        initialGroup: initial,
                        isShortAcronym: isShortAcronym
                    )
                )
            }
        }
        return targets
    }

    private func knownCanonicalTerms() -> Set<String> {
        var known = Set(words.map { $0.canonical.lowercased() })
        for pack in enabledPacks {
            guard let dict = packTerms[pack] else { continue }
            for canonical in dict.keys {
                known.insert(canonical.lowercased())
            }
        }
        return known
    }

    private func applyPhoneticRecovery(to text: String) -> String {
        guard !text.isEmpty else { return text }
        let targets = phoneticTargets()
        guard !targets.isEmpty else { return text }
        let tokens = Self.wordTokens(in: text)
        guard !tokens.isEmpty else { return text }

        let known = knownCanonicalTerms()
        var replacements: [(range: NSRange, replacement: String)] = []
        var idx = 0

        while idx < tokens.count {
            var matched: (spanCount: Int, range: NSRange, canonical: String)?

            for span in [3, 2, 1] where idx + span <= tokens.count {
                let slice = tokens[idx..<(idx + span)]
                let combinedNSRange = NSUnionRange(slice[slice.startIndex].range, slice[slice.endIndex - 1].range)
                let surface = (text as NSString).substring(with: combinedNSRange)
                let lowerSurface = surface.lowercased()

                if span == 1 && (Self.commonWords.contains(lowerSurface) || known.contains(lowerSurface)) {
                    continue
                }
                if span > 1 {
                    let lowerTokens = slice.map { $0.surface.lowercased() }
                    let allCommon = lowerTokens.allSatisfy { Self.commonWords.contains($0) }
                    if allCommon || slice.contains(where: { known.contains($0.surface.lowercased()) }) {
                        continue
                    }
                    // Preserve legitimate ordinary phrases like "the house" while allowing phrases such as "Point of Sale".
                    let hasNonConnectorContent = lowerTokens.contains { !Self.commonWords.contains($0) && !Self.connectorWords.contains($0) }
                    guard hasNonConnectorContent else { continue }
                }

                let norm = Self.normalizedAlphaNumeric(surface)
                guard norm.count >= 2 else { continue }
                if let candidate = Self.bestPhoneticMatch(
                    normalizedSurface: norm,
                    isMultiWord: span > 1,
                    targets: targets
                ) {
                    matched = (span, combinedNSRange, candidate)
                    break
                }
            }

            if let hit = matched {
                replacements.append((hit.range, hit.canonical))
                idx += hit.spanCount
            } else {
                idx += 1
            }
        }

        guard !replacements.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for item in replacements.reversed() {
            mutable.replaceCharacters(in: item.range, with: item.replacement)
        }
        return mutable as String
    }

    private static let tokenRegex = try? NSRegularExpression(pattern: #"[A-Za-z0-9'’]+"#, options: [])

    private static func wordTokens(in text: String) -> [(range: NSRange, surface: String, normalized: String)] {
        guard let tokenRegex else { return [] }
        let nsText = text as NSString
        let matches = tokenRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        return matches.map { match in
            let surface = nsText.substring(with: match.range)
            return (match.range, surface, normalizedAlphaNumeric(surface))
        }
    }

    private static func normalizedAlphaNumeric(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func phoneticSkeleton(_ normalized: String) -> String {
        var s = normalized
        for (pair, repl) in [
            ("ph", "f"), ("gh", "g"), ("kn", "n"), ("wr", "r"), ("sh", "x"),
            ("ch", "x"), ("ti", "x"), ("ci", "x"), ("qu", "k")
        ] {
            s = s.replacingOccurrences(of: pair, with: repl)
        }
        let mapChar: (Character) -> Character = { ch in
            switch ch {
            case "c", "q": return "k"
            case "z": return "s"
            case "w": return "v"
            case "d": return "t"
            case "b": return "p"
            case "j": return "g"
            default: return ch
            }
        }
        var out = ""
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        for (index, rawChar) in s.enumerated() {
            let mapped = mapChar(rawChar)
            if index > 0 && vowels.contains(mapped) { continue }
            if out.last != mapped { out.append(mapped) }
        }
        return out
    }

    private static func bestPhoneticMatch(
        normalizedSurface: String,
        isMultiWord: Bool,
        targets: [PhoneticTarget]
    ) -> String? {
        let surfaceSkel = phoneticSkeleton(normalizedSurface)
        guard let surfaceInit = surfaceSkel.first, !surfaceSkel.isEmpty else { return nil }
        var best: (canonical: String, score: Double)?

        for target in targets {
            if target.isShortAcronym {
                // Multi-word spaced acronyms ("s d k") allow skeleton match; single tokens require tight direct similarity so "app" never mutates into "API".
                let minLen = isMultiWord ? 2 : max(2, target.normalized.count)
                guard normalizedSurface.count >= minLen else { continue }
                let skelMatch = target.skeleton == surfaceSkel
                let dist = acousticEditDistance(normalizedSurface, target.normalized)
                if isMultiWord {
                    guard skelMatch || dist <= 0.6 else { continue }
                } else {
                    guard dist <= 0.45 else { continue }
                }
                guard target.initialGroup == surfaceInit || dist <= 0.45 else { continue }
                let score = 1.0 + (skelMatch ? 0.3 : 0.0) - dist * 0.25
                if best == nil || score > best!.score {
                    best = (target.canonical, score)
                }
                continue
            }

            guard normalizedSurface.count >= 4 else { continue }
            if abs(target.normalized.count - normalizedSurface.count) > 3 { continue }
            let skelMatch = target.skeleton == surfaceSkel
            let distance = acousticEditDistance(normalizedSurface, target.normalized)
            let maxLen = max(normalizedSurface.count, target.normalized.count)
            let similarity = 1.0 - distance / Double(max(1, maxLen))
            let maxEdits: Double = isMultiWord ? (skelMatch ? 2.2 : 1.15) : (maxLen <= 5 ? 1.0 : (maxLen <= 9 ? 2.0 : 3.0))
            let minSimilarity = isMultiWord ? 0.78 : (skelMatch ? 0.58 : 0.72)

            guard target.initialGroup == surfaceInit || distance <= 1.0 else { continue }
            guard distance <= maxEdits, similarity >= minSimilarity else { continue }
            if !skelMatch {
                let skelDistance = editDistance(surfaceSkel, target.skeleton)
                guard skelDistance <= 1 else { continue }
            }

            let score = similarity + (skelMatch ? 0.25 : 0.0)
            if best == nil || score > best!.score {
                best = (target.canonical, score)
            }
        }
        return best?.canonical
    }

    /// Folds common phonetic digraphs and geminate repeats (`ph->f`, `ck->k`, `ff->f`, `gg->g`) before edit distance.
    private static func acousticFold(_ input: String) -> [Character] {
        let folded = input
            .replacingOccurrences(of: "ph", with: "f")
            .replacingOccurrences(of: "ck", with: "k")
        var out: [Character] = []
        out.reserveCapacity(folded.count)
        for ch in folded where out.last != ch {
            out.append(ch)
        }
        return out
    }

    /// Weighted Damerau-Levenshtein distance accounting for common ASR acoustic consonant confusions.
    private static func acousticEditDistance(_ a: String, _ b: String) -> Double {
        let s = acousticFold(a)
        let t = acousticFold(b)
        if s.isEmpty { return Double(t.count) }
        if t.isEmpty { return Double(s.count) }
        let m = s.count
        let n = t.count
        var dp = Array(repeating: Array(repeating: 0.0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = Double(i) }
        for j in 0...n { dp[0][j] = Double(j) }

        for i in 1...m {
            for j in 1...n {
                let subCost = substitutionCost(s[i - 1], t[j - 1])
                var best = min(
                    dp[i - 1][j] + 1.0,
                    dp[i][j - 1] + 1.0,
                    dp[i - 1][j - 1] + subCost
                )
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    best = min(best, dp[i - 2][j - 2] + 0.55)
                }
                dp[i][j] = best
            }
        }
        return dp[m][n]
    }

    private static func substitutionCost(_ a: Character, _ b: Character) -> Double {
        if a == b { return 0.0 }
        let pair: Set<Character> = [a, b]
        let confusableGroups: [Set<Character>] = [
            ["p", "b"], ["t", "d"], ["f", "v"], ["s", "z"],
            ["k", "c", "q", "g"], ["m", "n"], ["w", "v"],
            ["a", "e", "i", "o", "u"]
        ]
        if confusableGroups.contains(where: { pair.isSubset(of: $0) }) {
            return 0.45
        }
        return 1.0
    }

    /// Extracts code/domain symbols (CamelCase, UPPERCASE acronyms, filenames) from an active window title.
    static func extractContextVocabulary(fromWindowTitle title: String?, maxTerms: Int = 12) -> [String] {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty, maxTerms > 0
        else { return [] }
        let pattern = #"\b(?:[A-Za-z0-9_]+\.[a-z]{1,6}|[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*|[A-Z]{2,}[0-9]*)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = title as NSString
        var out: [String] = []
        var seen = Set<String>()
        for match in regex.matches(in: title, range: NSRange(location: 0, length: ns.length)) {
            let tok = ns.substring(with: match.range)
            let key = tok.lowercased()
            guard !seen.contains(key), !commonWords.contains(key) else { continue }
            seen.insert(key)
            out.append(tok)
            if out.count >= maxTerms { break }
        }
        return out
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let s = Array(a)
        let t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var curr = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = curr
        }
        return prev[t.count]
    }

    // MARK: - Snippets

    func addSnippet(keyword: String, expansion: String) {
        let cleanKw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKw.isEmpty else { return }
        let snippet = DictationSnippet(keyword: cleanKw, expansion: expansion)
        snippets.append(snippet)
        saveSnippets()
    }

    func deleteSnippet(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        saveSnippets()
    }

    func applySnippets(_ text: String) -> String {
        guard !snippets.isEmpty else { return text }
        return Self.applyCompiled(snippetRules(), to: text)
    }

    private func loadSnippets() {
        if FileManager.default.fileExists(atPath: snippetsFileURL.path),
           let data = try? Data(contentsOf: snippetsFileURL),
           let list = try? JSONDecoder().decode([DictationSnippet].self, from: data) {
            snippets = list
        }
    }

    private func saveSnippets() {
        do {
            let dir = snippetsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(snippets)
            try data.write(to: snippetsFileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save dictation snippets: \(error.localizedDescription)")
        }
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
            // Object wrapper format { "words": [...] }
            struct WordsFileWrapper: Decodable {
                struct RawWord: Decodable {
                    let canonical: String
                    let aliases: [String]?
                    let category: String?
                }
                let words: [RawWord]
            }
            if let wrapper = try? JSONDecoder().decode(WordsFileWrapper.self, from: data) {
                for w in wrapper.words {
                    addWord(canonical: w.canonical, aliases: w.aliases ?? [], category: w.category ?? "general")
                    count += 1
                }
                return count
            }
        }

        // Plain text or CSV list: one per line ("canonical -> alias1, alias2", "canonical: alias", or CSV "canonical,alias1,alias2")
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
            } else if trimmed.contains(",") {
                let parts = trimmed.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if let canonical = parts.first {
                    addWord(canonical: canonical, aliases: Array(parts.dropFirst()))
                    count += 1
                }
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

    func exportToPlainText(to url: URL) throws {
        let lines = words.map { word in
            word.aliases.isEmpty ? word.canonical : "\(word.canonical) -> \(word.aliases.joined(separator: ", "))"
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
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

    func loadedTermsCount(for pack: VocabularyPackType) -> Int {
        packTerms[pack]?.count ?? 0
    }

    private func loadPacks() {
        let bundlePacksURL = Bundle.main.url(forResource: "Packs", withExtension: nil)
            ?? Bundle.main.resourceURL?.appendingPathComponent("Packs")

        let devTreeURL: URL? = {
            let currentFile = URL(fileURLWithPath: #filePath)
            // #filePath: .../szcast/Features/Dictation/Service/DictationDictionaryStore.swift
            let root = currentFile
                .deletingLastPathComponent() // Service
                .deletingLastPathComponent() // Dictation
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // szcast
            return root.appendingPathComponent("Resources/Packs")
        }()

        let appSupportPacksURL = AppPaths.applicationSupport().appendingPathComponent("Packs")

        for pack in VocabularyPackType.allCases {
            var loaded = false
            let filename = "\(pack.rawValue).json"

            let candidates: [URL?] = [
                bundlePacksURL?.appendingPathComponent(filename),
                Bundle.main.url(forResource: pack.rawValue, withExtension: "json", subdirectory: "Packs"),
                Bundle.main.url(forResource: pack.rawValue, withExtension: "json"),
                devTreeURL?.appendingPathComponent(filename),
                appSupportPacksURL.appendingPathComponent(filename)
            ]

            for candidate in candidates.compactMap({ $0 }) {
                if FileManager.default.fileExists(atPath: candidate.path),
                   let data = try? Data(contentsOf: candidate),
                   let dict = try? JSONDecoder().decode([String: [String]].self, from: data),
                   !dict.isEmpty {
                    packTerms[pack] = dict
                    loaded = true
                    Self.logger.info("Loaded \(dict.count) terms for pack '\(pack.rawValue)' from \(candidate.path)")
                    break
                }
            }

            if !loaded {
                packTerms[pack] = Self.starterPackTerms(for: pack)
            }
        }
    }

    private static func starterPackTerms(for pack: VocabularyPackType) -> [String: [String]] {
        switch pack {
        case .tech:
            return [
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
        case .aiMl:
            return [
                "PyTorch": ["pie torch", "py torch", "pi torch"],
                "CoreML": ["core ml", "core m l", "core mail"],
                "Claude": ["clod", "claud", "cloud code"],
                "Antigravity": ["anti gravity", "anti-gravity"],
                "Parakeet": ["para keet", "para kit"],
                "Nemotron": ["nemo tron", "nimotron"],
                "Qwen": ["kwin", "qwen 3", "quinn"],
                "LangChain": ["lang chain", "long chain"],
                "RAG": ["r a g", "rag pipeline"],
                "LoRA": ["lora", "low rank adapter"],
                "GGUF": ["g g u f", "g guf"],
                "MCP": ["m c p", "mcp server"],
                "Whisper": ["wisper", "whispr"],
                "vDSP": ["v dsp", "v d s p"],
                "Silero": ["salero", "silero vad"],
                "LLM": ["l l m", "large language model"]
            ]
        case .finance:
            return [
                "EBITDA": ["ebita", "ebit da", "e bit da"],
                "WACC": ["wack", "w a c c"],
                "CAGR": ["kager", "cager", "c a g r"],
                "DCF": ["d c f", "discounted cash flow"],
                "ROIC": ["r o i c", "roic"],
                "CAPEX": ["cap ex", "cap-ex"],
                "OPEX": ["op ex", "op-ex"],
                "ARR": ["a r r"],
                "MRR": ["m r r"],
                "NPV": ["n p v"],
                "IRR": ["i r r"],
                "LTV": ["l t v"],
                "CAC": ["c a c", "customer acquisition cost"],
                "YoY": ["y o y", "year over year"],
                "QoQ": ["q o q", "quarter over quarter"],
                "P&L": ["p and l", "p n l"]
            ]
        case .medical:
            return [
                "acetaminophen": ["acidaminophan", "acidaminophen"],
                "amoxicillin": ["amaxicylin", "amaxisillin"],
                "Celexa": ["celex", "selexa"],
                "Fosamax": ["fosemax", "phosamax"],
                "Humira": ["humera", "hewmera"],
                "ibuprofen": ["eyebuprofen", "ibiprofen"]
            ]
        case .legal:
            return [
                "FERPA": ["furpa", "ferpah"],
                "NLRB": ["nl rb", "n l r b"],
                "accord": ["archord", "eccord"],
                "appellate": ["epilati", "ipolate"],
                "affidavit": ["afadavit", "affadavit"]
            ]
        case .brands:
            return [
                "adidas": ["addides", "adidos"],
                "Adyen": ["adeyan", "adiane", "adyne"],
                "Aetna": ["ayatna", "eatner", "oatna"],
                "ASUS": ["asus", "eissus", "ay-soos"],
                "Raycast": ["ray cast", "recast"],
                "szcast": ["sz cast", "s z cast", "tinycast"]
            ]
        case .names:
            return [
                "Acosta": ["acosto", "acusti", "ecosta"],
                "Adeline": ["edline", "odline"],
                "Aguirre": ["aguary", "agwara", "aquari"],
                "Saurav": ["sourab", "sourav", "saurabh"]
            ]
        }
    }
}
