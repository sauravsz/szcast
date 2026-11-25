import Foundation

struct TranscriptWord: Codable, Equatable, Hashable, Sendable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var confidence: Float

    init(text: String, start: TimeInterval, end: TimeInterval, confidence: Float = 1.0) {
        self.text = text
        self.start = max(0, start)
        self.end = max(self.start, end)
        self.confidence = confidence
    }
}

struct SpeakerTurn: Codable, Equatable, Hashable, Sendable {
    var speaker: String
    var start: TimeInterval
    var end: TimeInterval

    init(speaker: String, start: TimeInterval, end: TimeInterval) {
        self.speaker = speaker
        self.start = max(0, start)
        self.end = max(self.start, end)
    }
}

struct TranscriptSegment: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var speaker: String
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var words: [TranscriptWord]

    var duration: TimeInterval { max(0, end - start) }

    init(
        id: UUID = UUID(),
        speaker: String = "",
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        words: [TranscriptWord] = []
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.start = max(0, start)
        self.end = max(self.start, end)
        self.words = words
    }
}

struct TimedTranscript: Codable, Equatable, Sendable {
    var text: String
    var words: [TranscriptWord]
    var segments: [TranscriptSegment]

    init(text: String, words: [TranscriptWord] = [], segments: [TranscriptSegment] = []) {
        self.text = text
        self.words = words
        if !segments.isEmpty {
            self.segments = segments
        } else if !words.isEmpty {
            self.segments = TranscriptSegmentBuilder.build(words: words, fallbackText: text)
        } else if !text.isEmpty {
            self.segments = [TranscriptSegment(speaker: "", text: text, start: 0, end: 0)]
        } else {
            self.segments = []
        }
    }
}

enum TranscriptRecordKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case dictation
    case meeting
    case fileImport
    case urlImport
    case podcastImport

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dictation: "Dictation"
        case .meeting: "Meeting"
        case .fileImport: "File"
        case .urlImport: "URL"
        case .podcastImport: "Podcast"
        }
    }

    var symbol: String {
        switch self {
        case .dictation: "mic"
        case .meeting: "person.2"
        case .fileImport: "doc.text"
        case .urlImport: "link"
        case .podcastImport: "antenna.radiowaves.left.and.right"
        }
    }
}

struct TranscriptRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: TranscriptRecordKind
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var text: String
    var rawText: String
    var summary: String
    var actionItems: [String]
    var decisions: [String]
    var segments: [TranscriptSegment]
    var sourceURL: String?
    var audioFilename: String?
    var appName: String?
    var appBundleID: String?
    var modelID: String?
    var wordCount: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: TranscriptRecordKind = .dictation,
        title: String = "",
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        text: String,
        rawText: String = "",
        summary: String = "",
        actionItems: [String] = [],
        decisions: [String] = [],
        segments: [TranscriptSegment] = [],
        sourceURL: String? = nil,
        audioFilename: String? = nil,
        appName: String? = nil,
        appBundleID: String? = nil,
        modelID: String? = nil,
        wordCount: Int? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.isEmpty ? Self.defaultTitle(for: cleanText, kind: kind, date: createdAt) : title
        self.createdAt = createdAt
        self.duration = max(0, duration)
        self.text = text
        self.rawText = rawText.isEmpty ? text : rawText
        self.summary = summary
        self.actionItems = actionItems
        self.decisions = decisions
        if !segments.isEmpty {
            self.segments = segments
        } else if !text.isEmpty {
            self.segments = [TranscriptSegment(speaker: "", text: text, start: 0, end: max(0, duration))]
        } else {
            self.segments = []
        }
        self.sourceURL = sourceURL
        self.audioFilename = audioFilename
        self.appName = appName
        self.appBundleID = appBundleID
        self.modelID = modelID
        self.wordCount = wordCount ?? text.split(whereSeparator: \.isWhitespace).count
        self.updatedAt = updatedAt ?? createdAt
    }

    var speakerNames: [String] {
        var seen = Set<String>()
        var result = [String]()
        for segment in segments {
            let clean = segment.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean).inserted else { continue }
            result.append(clean)
        }
        return result
    }

    func renamingSpeaker(_ oldSpeaker: String, to newSpeaker: String) -> TranscriptRecord {
        let trimmed = newSpeaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldSpeaker else { return self }
        var copy = self
        copy.segments = segments.map { segment in
            guard segment.speaker == oldSpeaker else { return segment }
            var next = segment
            next.speaker = trimmed
            return next
        }
        copy.updatedAt = Date()
        return copy
    }

    func replacingOccurrences(
        of needle: String, with replacement: String, caseSensitive: Bool
    ) -> (record: TranscriptRecord, replacements: Int) {
        guard !needle.isEmpty else { return (self, 0) }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var copy = self
        var count = 0

        func replaceAll(in value: String) -> (String, Int) {
            var updated = value
            var hits = 0
            var searchStart = updated.startIndex
            while searchStart < updated.endIndex,
                let range = updated.range(of: needle, options: options, range: searchStart..<updated.endIndex)
            {
                updated.replaceSubrange(range, with: replacement)
                hits += 1
                searchStart = updated.index(range.lowerBound, offsetBy: replacement.count, limitedBy: updated.endIndex)
                    ?? updated.endIndex
            }
            return (updated, hits)
        }

        let (newText, textHits) = replaceAll(in: text)
        copy.text = newText
        count += textHits
        copy.segments = segments.map { segment in
            var next = segment
            let (segText, _) = replaceAll(in: segment.text)
            next.text = segText
            next.words = segment.words.map { word in
                var w = word
                w.text = replaceAll(in: word.text).0
                return w
            }
            return next
        }
        if count > 0 {
            copy.wordCount = copy.text.split(whereSeparator: \.isWhitespace).count
            copy.updatedAt = Date()
        }
        return (copy, count)
    }

    static func defaultTitle(for text: String, kind: TranscriptRecordKind, date: Date) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).prefix(8).joined(separator: " ")
        if !words.isEmpty {
            return words.count > 64 ? String(words.prefix(64)) + "…" : words
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(kind.label) — \(formatter.string(from: date))"
    }
}

enum TranscriptTimeFormat {
    static func formatSRT(_ seconds: TimeInterval) -> String {
        format(seconds, decimalSeparator: ",")
    }

    static func formatVTT(_ seconds: TimeInterval) -> String {
        format(seconds, decimalSeparator: ".")
    }

    static func formatClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    static func formatISO8601Duration(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3600
        let mins = (Int(clamped) % 3600) / 60
        let rem = clamped - Double(hours * 3600 + mins * 60)
        var out = "PT"
        if hours > 0 { out += "\(hours)H" }
        if mins > 0 || hours > 0 { out += "\(mins)M" }
        out += String(format: "%.3fS", rem)
        return out
    }

    private static func format(_ seconds: TimeInterval, decimalSeparator: String) -> String {
        let totalMs = max(0, Int((seconds * 1000).rounded()))
        let hours = totalMs / 3_600_000
        let mins = (totalMs % 3_600_000) / 60_000
        let secs = (totalMs % 60_000) / 1_000
        let ms = totalMs % 1_000
        return String(format: "%02d:%02d:%02d%@%03d", hours, mins, secs, decimalSeparator, ms)
    }
}

enum TranscriptSegmentBuilder {
    static func build(
        words: [TranscriptWord],
        turns: [SpeakerTurn] = [],
        fallbackText: String = "",
        maxSegmentWords: Int = 18,
        pauseThreshold: TimeInterval = 0.85
    ) -> [TranscriptSegment] {
        guard !words.isEmpty else {
            let trimmed = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            let speaker = turns.first?.speaker ?? ""
            return [TranscriptSegment(
                speaker: speaker,
                text: trimmed,
                start: turns.first?.start ?? 0,
                end: turns.last?.end ?? 0
            )]
        }

        var segments = [TranscriptSegment]()
        var bucket = [TranscriptWord]()
        var bucketSpeaker = turns.isEmpty ? "" : speakerForWord(words[0], in: turns)

        func flush() {
            guard !bucket.isEmpty else { return }
            let joined = joinWords(bucket)
            if !joined.isEmpty {
                segments.append(TranscriptSegment(
                    speaker: bucketSpeaker,
                    text: joined,
                    start: bucket[0].start,
                    end: bucket[bucket.count - 1].end,
                    words: bucket
                ))
            }
            bucket.removeAll(keepingCapacity: true)
        }

        for word in words {
            let speaker = turns.isEmpty ? "" : speakerForWord(word, in: turns)
            let previous = bucket.last
            let speakerChanged = !bucket.isEmpty && speaker != bucketSpeaker
            let longPause = previous.map { word.start - $0.end >= pauseThreshold } ?? false
            let endedSentence = previous.map { endsSentence($0.text) } ?? false
            let reachedLimit = bucket.count >= maxSegmentWords && (previous?.start ?? 0) < word.start

            if speakerChanged || longPause || (endedSentence && bucket.count >= 4) || reachedLimit {
                flush()
                bucketSpeaker = speaker
            }
            bucket.append(word)
        }
        flush()
        return segments
    }

    /// Merges subword pieces starting with SentencePiece `▁` into timed whole words.
    static func mergeSubwordPieces(_ pieces: [(piece: String, start: TimeInterval, end: TimeInterval)]) -> [TranscriptWord] {
        var words = [TranscriptWord]()
        var currentText = ""
        var currentStart: TimeInterval = 0
        var currentEnd: TimeInterval = 0

        func flush() {
            let clean = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            words.append(TranscriptWord(text: clean, start: currentStart, end: max(currentStart, currentEnd)))
            currentText = ""
        }

        for entry in pieces {
            let raw = entry.piece
            let startsNewWord = raw.hasPrefix("▁") || raw.hasPrefix(" ") || currentText.isEmpty
            let cleanPiece = raw.replacingOccurrences(of: "▁", with: " ")
            if startsNewWord {
                flush()
                currentText = cleanPiece.trimmingCharacters(in: .whitespaces)
                currentStart = entry.start
                currentEnd = entry.end
            } else {
                currentText += cleanPiece
                currentEnd = max(currentEnd, entry.end)
            }
        }
        flush()
        return words
    }

    static func mergeTracks(mic: [TranscriptSegment], system: [TranscriptSegment]) -> [TranscriptSegment] {
        let labeledMic = mic.map { seg -> TranscriptSegment in
            var copy = seg
            if copy.speaker.isEmpty { copy.speaker = "Me" }
            return copy
        }
        let labeledSystem = system.map { seg -> TranscriptSegment in
            var copy = seg
            if copy.speaker.isEmpty { copy.speaker = "Others" }
            return copy
        }
        return (labeledMic + labeledSystem).sorted { lhs, rhs in
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }
    }

    private static func speakerForWord(_ word: TranscriptWord, in turns: [SpeakerTurn]) -> String {
        let wordEnd = max(word.end, word.start + 0.05)
        var bestSpeaker = ""
        var bestOverlap: TimeInterval = 0
        for turn in turns {
            let overlap = min(wordEnd, turn.end) - max(word.start, turn.start)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = turn.speaker
            }
        }
        if !bestSpeaker.isEmpty { return bestSpeaker }
        let midpoint = (word.start + wordEnd) * 0.5
        if let nearest = turns.min(by: {
            distance(from: midpoint, to: $0) < distance(from: midpoint, to: $1)
        }), distance(from: midpoint, to: nearest) <= 0.45 {
            return nearest.speaker
        }
        return "Unattributed"
    }

    private static func distance(from point: TimeInterval, to turn: SpeakerTurn) -> TimeInterval {
        if point < turn.start { return turn.start - point }
        if point > turn.end { return point - turn.end }
        return 0
    }

    private static func joinWords(_ words: [TranscriptWord]) -> String {
        var out = ""
        let noLeadingSpace = CharacterSet(charactersIn: ".,!?;:)]}%”’'")
        for word in words {
            let clean = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            if out.isEmpty {
                out = clean
            } else if let first = clean.unicodeScalars.first, noLeadingSpace.contains(first),
                clean.count == 1 || first == "." || first == "," || first == "?" || first == "!"
            {
                out += clean
            } else {
                out += " " + clean
            }
        }
        return out
    }

    private static func endsSentence(_ text: String) -> Bool {
        text.hasSuffix(".") || text.hasSuffix("?") || text.hasSuffix("!")
    }
}
