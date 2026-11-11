import Foundation

enum DictationTextFormatter {
    struct Context: Sendable {
        let trailing: Character?
        let lastNonWhitespace: Character?
        let newParagraph: Bool
        let following: Character?

        init(before: Substring, after: Substring) {
            trailing = before.last
            following = after.first
            var last: Character?
            var paragraph = false
            for character in before.reversed() {
                if !character.isWhitespace {
                    last = character
                    break
                }
                if character.isNewline { paragraph = true }
            }
            lastNonWhitespace = last
            newParagraph = paragraph
        }
    }

    // MARK: - Spoken Emoji

    private static let emojiDictionary: [(phrase: String, glyph: String)] = [
        ("thumbs up", "👍"),
        ("thumbs down", "👎"),
        ("red heart", "❤️"),
        ("sparkling heart", "💖"),
        ("heart", "❤️"),
        ("fire", "🔥"),
        ("smiling face", "😊"),
        ("happy face", "😊"),
        ("smile", "😊"),
        ("laughing face", "😂"),
        ("laugh", "😂"),
        ("crying face", "😭"),
        ("crying", "😭"),
        ("wink", "😉"),
        ("rocket", "🚀"),
        ("party", "🎉"),
        ("celebration", "🎉"),
        ("check mark", "✅"),
        ("cross mark", "❌"),
        ("eyes", "👀"),
        ("clapping", "👏"),
        ("clap", "👏"),
        ("muscle", "💪"),
        ("flex", "💪"),
        ("star", "⭐"),
        ("sparkles", "✨"),
        ("100", "💯"),
        ("hundred", "💯"),
        ("coffee", "☕"),
        ("beer", "🍺"),
        ("pizza", "🍕"),
        ("sun", "☀️"),
        ("moon", "🌙"),
        ("flag", "🚩"),
        ("thinking face", "🤔"),
        ("thinking", "🤔"),
        ("folded hands", "🙏"),
        ("pray", "🙏"),
        ("salute", "🫡"),
        ("skull", "💀"),
        ("shrug", "🤷"),
        ("facepalm", "🤦"),
        ("wave", "👋"),
        ("raised hand", "✋"),
        ("ok hand", "👌"),
        ("peace", "✌️")
    ]

    static func convertSpokenEmoji(_ text: String) -> String {
        guard text.localizedCaseInsensitiveContains("emoji") || text.localizedCaseInsensitiveContains("emoticon") else {
            return text
        }
        var result = text
        // Sort longer phrases first to avoid partial matches
        let sorted = emojiDictionary.sorted { $0.phrase.count > $1.phrase.count }
        for (phrase, glyph) in sorted {
            let patterns = [
                #"\b"# + NSRegularExpression.escapedPattern(for: phrase) + #"\s+(?:emoji|emoticon)\b"#,
                #"\b(?:emoji|emoticon)\s+"# + NSRegularExpression.escapedPattern(for: phrase) + #"\b"#
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let range = NSRange(result.startIndex..<result.endIndex, in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: glyph)
                }
            }
        }
        return result
    }

    // MARK: - Spoken Punctuation

    private static let punctuationCommands: [(pattern: String, replacement: String)] = [
        (#"\b(?:new paragraph|paragraph break)\b"#, "\n\n"),
        (#"\b(?:new line|line break)\b"#, "\n"),
        (#"\b(?:question mark)\b"#, "?"),
        (#"\b(?:exclamation mark|exclamation point)\b"#, "!"),
        (#"\b(?:period|full stop)\b"#, "."),
        (#"\b(?:comma)\b"#, ","),
        (#"\b(?:colon)\b"#, ":"),
        (#"\b(?:semicolon)\b"#, ";"),
        (#"\b(?:ellipsis|dot dot dot)\b"#, "…"),
        (#"\b(?:open parenthesis|open paren)\b"#, "("),
        (#"\b(?:close parenthesis|close paren)\b"#, ")"),
        (#"\b(?:open bracket|open square bracket)\b"#, "["),
        (#"\b(?:close bracket|close square bracket)\b"#, "]"),
        (#"\b(?:open brace|open curly bracket)\b"#, "{"),
        (#"\b(?:close brace|close curly bracket)\b"#, "}"),
        (#"\b(?:open quote|open quotation mark)\b"#, "\""),
        (#"\b(?:close quote|close quotation mark)\b"#, "\""),
        (#"\b(?:single quote|apostrophe)\b"#, "'"),
        (#"\b(?:em dash)\b"#, "—"),
        (#"\b(?:hyphen|dash)\b"#, "-"),
        (#"\b(?:ampersand)\b"#, "&"),
        (#"\b(?:plus sign)\b"#, "+"),
        (#"\b(?:equals sign)\b"#, "="),
        (#"\b(?:asterisk)\b"#, "*"),
        (#"\b(?:hashtag|hash sign)\b"#, "#"),
        (#"\b(?:tilde)\b"#, "~")
    ]

    static func convertSpokenPunctuation(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in punctuationCommands {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }
        // Cleanup whitespace before punctuation: e.g. "word ," -> "word,"
        if let regex = try? NSRegularExpression(pattern: #"\s+([,.:;?!…\)])"#, options: []) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        // Cleanup whitespace after opening brackets: e.g. "( word" -> "(word"
        if let regex = try? NSRegularExpression(pattern: #"([\(\[\{])\s+"#, options: []) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        return result
    }

    // MARK: - Filler Words Removal

    private static let fillerRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(?:^|\s*)((?:\b(?:um|umm|uh|uhh|hmm|mhm|mmm|er)\b)|(?:(?<![0-9])(?<![0-9] )(?<![0-9]-)\b(?:mm|ah)\b))[-.,!?…:;—]*(?=\s|$)"#,
            options: [.caseInsensitive]
        )
    }()

    static func removeFillerWords(_ text: String) -> String {
        guard let regex = fillerRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        // Normalize any collapsed double spaces
        return cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Echo Stripping

    static func stripEcho(_ text: String, after previous: String) -> String {
        guard !text.isEmpty, !previous.isEmpty else { return text }
        let tail = Array(previous.split(separator: " ").suffix(8))
        let head = Array(text.split(separator: " "))
        let plain = { (word: Substring) in
            word.lowercased().trimmingCharacters(in: .alphanumerics.inverted)
        }
        var drop = 0
        for skip in 0..<min(3, head.count) {
            let minimum = skip == 0 ? 1 : skip + 1
            var run = min(tail.count, head.count - skip)
            while run >= minimum {
                guard
                    (0..<run).allSatisfy({ plain(head[skip + $0]) == plain(tail[tail.count - run + $0]) })
                else {
                    run -= 1
                    continue
                }
                drop = max(drop, skip + run)
                break
            }
        }
        guard drop > 0 else { return text }
        var index = text.startIndex
        for _ in 0..<drop {
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }
        }
        let rest = String(text[index...])
        return rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : rest
    }

    // MARK: - Smart Caret Insertion

    static func format(_ transcription: String, context: Context?, adaptCapitalization: Bool = true) -> String {
        var text = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let context else { return text }
        if adaptCapitalization, let first = text.first, first.isLetter {
            let replacement: String
            if context.lastNonWhitespace == nil || context.newParagraph
                || context.lastNonWhitespace.map({ ".!?".contains($0) }) == true
            {
                replacement = String(first).uppercased()
            } else {
                replacement = String(first).lowercased()
            }
            text.replaceSubrange(text.startIndex...text.startIndex, with: replacement)
        }
        if let trailing = context.trailing, !trailing.isWhitespace,
            !"([{/\"'‘’“—-".contains(trailing),
            let leading = text.first, !".,!?;:)]}/\"'”".contains(leading)
        {
            text = " " + text
        }
        if let leading = context.following, !leading.isWhitespace,
            let trailing = text.last, !trailing.isWhitespace,
            !".,!?;:)]}/\"'”".contains(leading)
        {
            text += " "
        }
        return text
    }
}
