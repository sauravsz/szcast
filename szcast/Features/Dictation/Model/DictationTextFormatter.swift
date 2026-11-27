import Foundation

enum DictationTextFormatter {
    enum VoiceMetaCommand: Equatable, Sendable {
        case undoLast
        case selectAll
        case copyThat
        case newTab
    }

    struct Context: Sendable {
        let trailing: Character?
        let lastNonWhitespace: Character?
        let newParagraph: Bool
        let following: Character?
        let currentLinePrefix: String

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
            if let lastNL = before.lastIndex(where: \.isNewline) {
                currentLinePrefix = String(before[before.index(after: lastNL)...])
            } else {
                currentLinePrefix = String(before)
            }
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

    private static let compiledEmojiRules: [(regex: NSRegularExpression, template: String)] = {
        let sorted = emojiDictionary.sorted { $0.phrase.count > $1.phrase.count }
        var rules: [(regex: NSRegularExpression, template: String)] = []
        rules.reserveCapacity(sorted.count * 2)
        for (phrase, glyph) in sorted {
            let escaped = NSRegularExpression.escapedPattern(for: phrase)
            let template = NSRegularExpression.escapedTemplate(for: glyph)
            let suffixPattern = #"\b"# + escaped + #"\s+(?:emoji|emoticon)\b"#
            let prefixPattern = #"\b(?:emoji|emoticon)\s+"# + escaped + #"\b"#
            for pattern in [suffixPattern, prefixPattern] {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    rules.append((regex: regex, template: template))
                }
            }
        }
        return rules
    }()

    static func convertSpokenEmoji(_ text: String) -> String {
        guard text.localizedCaseInsensitiveContains("emoji") || text.localizedCaseInsensitiveContains("emoticon") else {
            return text
        }
        var result = text
        for rule in compiledEmojiRules {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = rule.regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.template)
        }
        return result
    }

    // MARK: - Spoken Punctuation & Wispr-Style Formatting

    private static let quoteOpenMarker = "\u{E001}"
    private static let quoteCloseMarker = "\u{E002}"
    private static let singleQuoteOpenMarker = "\u{E003}"
    private static let singleQuoteCloseMarker = "\u{E004}"
    private static let slashMarker = "\u{E005}"
    private static let backslashMarker = "\u{E006}"
    private static let underscoreMarker = "\u{E007}"
    private static let bulletMarker = "\u{E008}"

    private static let punctuationCommands: [(pattern: String, replacement: String)] = [
        // Structural breaks & lists (longest multi-word matches first)
        (#"\b(?:new paragraph|paragraph break|next paragraph)\b"#, "\n\n"),
        (#"\b(?:new line|line break|next line)\b"#, "\n"),
        (#"\b(?:bullet point|new bullet|bullet item)\b"#, bulletMarker),
        (#"\b(?:tab key)\b"#, "\t"),

        // Specific bracket families BEFORE generic parentheses ("bracket")
        (#"\b(?:(?:a|an|the)\s+)?(?:(?:open(?:ing)?|start|begin)\s+square\s+bracket(?:s)?|square\s+bracket\s+(?:start|begin|open(?:s)?))\b"#, "["),
        (#"\b(?:the\s+)?(?:(?:clos(?:e|ing)|end(?:ing)?)\s+square\s+bracket(?:s)?|square\s+bracket\s+(?:clos(?:e|ed|es)|end(?:s)?|finish))\b"#, "]"),
        (#"\b(?:(?:a|an|the)\s+)?(?:(?:open(?:ing)?|start|begin)\s+(?:curly\s+bracket|curly\s+brace|brace)(?:s)?|(?:curly\s+bracket|curly\s+brace|brace)\s+(?:start|begin|open(?:s)?))\b"#, "{"),
        (#"\b(?:the\s+)?(?:(?:clos(?:e|ing)|end(?:ing)?)\s+(?:curly\s+bracket|curly\s+brace|brace)(?:s)?|(?:curly\s+bracket|curly\s+brace|brace)\s+(?:clos(?:e|ed|es)|end(?:s)?|finish))\b"#, "}"),
        (#"\b(?:(?:a|an|the)\s+)?(?:(?:open(?:ing)?|start|begin)\s+angle\s+bracket(?:s)?|angle\s+bracket\s+(?:start|begin|open(?:s)?))\b"#, "<"),
        (#"\b(?:the\s+)?(?:(?:clos(?:e|ing)|end(?:ing)?)\s+angle\s+bracket(?:s)?|angle\s+bracket\s+(?:clos(?:e|ed|es)|end(?:s)?|finish))\b"#, ">"),

        // Parentheses & everyday "(a) bracket start ... bracket close"
        (#"\b(?:(?:a|an|the)\s+)?(?:(?:open(?:ing)?|start|begin)\s+(?:parenthesis|parentheses|paren|parens|bracket|brackets)|(?:parenthesis|parentheses|paren|parens|bracket|brackets)\s+(?:start|starts|begin|begins|open|opens))\b"#, "("),
        (#"\b(?:the\s+)?(?:(?:clos(?:e|ing)|end(?:ing)?|stop)\s+(?:parenthesis|parentheses|paren|parens|bracket|brackets)|(?:parenthesis|parentheses|paren|parens|bracket|brackets)\s+(?:close|closed|closes|end|ends|finish|stop))\b"#, ")"),

        // Quotes (single before double, or distinct multi-word phrases)
        (#"\b(?:open(?:ing)?\s+single\s+quote|single\s+quote\s+start|begin\s+single\s+quote|start\s+single\s+quote)\b"#, singleQuoteOpenMarker),
        (#"\b(?:clos(?:e|ing)\s+single\s+quote|end\s+single\s+quote|single\s+quote\s+(?:close|end))\b"#, singleQuoteCloseMarker),
        (#"\b(?:open(?:ing)?\s+(?:double\s+)?(?:quote|quotation\s+mark)|(?:double\s+)?quote\s+start|start\s+(?:double\s+)?quote|begin\s+(?:double\s+)?quote)\b"#, quoteOpenMarker),
        (#"\b(?:clos(?:e|ing)\s+(?:double\s+)?(?:quote|quotation\s+mark)|end\s+(?:double\s+)?quote|(?:double\s+)?quote\s+(?:close|end))\b"#, quoteCloseMarker),
        (#"\b(?:apostrophe)\b"#, "'"),

        // Standard punctuation
        (#"\b(?:question\s+mark)\b"#, "?"),
        (#"\b(?:exclamation\s+(?:mark|point))\b"#, "!"),
        (#"\b(?:ellipsis|dot\s+dot\s+dot)\b"#, "…"),
        (#"\b(?:semicolon|semi\s+colon)\b"#, ";"),
        (#"\b(?:colon\s+sign|colon)\b"#, ":"),
        (#"\b(?:comma)\b"#, ","),
        (#"\b(?:period|full\s+stop)\b"#, "."),

        // Slashes, dashes & symbols
        (#"\b(?:backslash|back\s+slash)\b"#, backslashMarker),
        (#"\b(?:forward\s+slash|front\s+slash|slash)\b"#, slashMarker),
        (#"\b(?:em\s+dash)\b"#, "—"),
        (#"\b(?:en\s+dash)\b"#, "–"),
        (#"\b(?:hyphen|dash\s+mark)\b"#, "-"),
        (#"\b(?:at\s+the\s+rate|at\s+sign)\b"#, "@"),
        (#"\b(?:underscore(?:\s+sign)?)\b"#, underscoreMarker),
        (#"\b(?:ampersand|and\s+sign)\b"#, "&"),
        (#"\b(?:plus\s+sign)\b"#, "+"),
        (#"\b(?:equals\s+sign|equal\s+sign)\b"#, "="),
        (#"\b(?:asterisk|star\s+sign)\b"#, "*"),
        (#"\b(?:hashtag(?:\s+sign)?|hash\s+sign|pound\s+sign)\b"#, "#"),
        (#"\b(?:percent\s+sign|percentage\s+sign)\b"#, "%"),
        (#"\b(?:indian\s+rupee\s+sign|rupee\s+sign)\b"#, "₹"),
        (#"\b(?:dollar\s+sign)\b"#, "$"),
        (#"\b(?:euro\s+sign)\b"#, "€"),
        (#"\b(?:pound\s+sterling\s+sign)\b"#, "£"),
        (#"\b(?:copyright\s+(?:sign|symbol))\b"#, "©"),
        (#"\b(?:registered\s+(?:trademark|sign|symbol))\b"#, "®"),
        (#"\b(?:trademark\s+(?:sign|symbol))\b"#, "™"),
        (#"\b(?:section\s+(?:sign|symbol))\b"#, "§"),
        (#"\b(?:division\s+(?:sign|symbol)|divided\s+by\s+(?:sign|symbol))\b"#, "÷"),
        (#"\b(?:multiplication\s+(?:sign|symbol))\b"#, "×"),
        (#"\b(?:plus\s+(?:or\s+)?minus\s+(?:sign|symbol))\b"#, "±"),
        (#"\b(?:greater\s+than\s+sign)\b"#, ">"),
        (#"\b(?:less\s+than\s+sign)\b"#, "<"),
        (#"\b(?:vertical\s+bar|pipe\s+(?:symbol|sign))\b"#, "|"),
        (#"\b(?:caret\s+sign)\b"#, "^"),
        (#"\b(?:degrees?\s+sign)\b"#, "°"),
        (#"\b(?:tilde)\b"#, "~")
    ]

    private static let compiledPunctuationRules: [(regex: NSRegularExpression, template: String)] = {
        punctuationCommands.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { return nil }
            return (regex: regex, template: NSRegularExpression.escapedTemplate(for: replacement))
        }
    }()

    private static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20
    ]

    private static let romanHomophones: [String: Int] = [
        "won": 1, "to": 2, "too": 2, "for": 4, "fore": 4, "ate": 8
    ]

    private static let romanValues: [String: Int] = [
        "i": 1, "ii": 2, "iii": 3, "iv": 4, "v": 5,
        "vi": 6, "vii": 7, "viii": 8, "ix": 9, "x": 10,
        "xi": 11, "xii": 12, "xiii": 13, "xiv": 14, "xv": 15,
        "xvi": 16, "xvii": 17, "xviii": 18, "xix": 19, "xx": 20
    ]

    private static let romanNumerals = [
        "", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
        "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"
    ]

    private static let romanCommandRegex = try? NSRegularExpression(
        pattern: #"\broman\s+numerals?\s+([a-z0-9]+)\b"#,
        options: [.caseInsensitive]
    )
    private static let columnCommandRegex = try? NSRegularExpression(
        pattern: #"\bcolumn\s+(?:number\s+)?([a-z0-9]+)\b"#,
        options: [.caseInsensitive]
    )
    private static let arabicNumeralCommandRegex = try? NSRegularExpression(
        pattern: #"\bnumeral\s+([a-z0-9]+)\b"#,
        options: [.caseInsensitive]
    )
    private static let allCapsWordRegex = try? NSRegularExpression(
        pattern: #"\ball\s+caps\s+([a-zA-Z0-9_-]+)\b"#,
        options: [.caseInsensitive]
    )

    private static let spaceBeforePunctRegex = try? NSRegularExpression(
        pattern: #"[ \t]+([,.:;?!…\)\]\}])"#, options: []
    )
    private static let spaceAfterBracketRegex = try? NSRegularExpression(
        pattern: #"([\(\[\{])[ \t]+"#, options: []
    )
    private static let commaInsideBracketRegex = try? NSRegularExpression(
        pattern: #"([\(\[\{]),[ \t]*"#, options: []
    )
    private static let commaBeforeClosingBracketRegex = try? NSRegularExpression(
        pattern: #",[ \t]*([\)\]\}])"#, options: []
    )
    private static let missingSpaceAfterSentenceRegex = try? NSRegularExpression(
        pattern: #"(?<=[a-z0-9"'\)\]\}])[.?!](?=[A-Z\p{Lu}])"#, options: []
    )
    private static let inlineSlashSpacingRegex = try? NSRegularExpression(
        pattern: #"(?<=[\p{L}\p{N}\)\]])[ \t]+/[ \t]+(?=[\p{L}\p{N}\(\[])"#, options: []
    )
    private static let prefixSymbolSpaceRegex = try? NSRegularExpression(
        pattern: #"(?:(?<=^)|(?<=[\s\(\[\{]))([$€£₹#@])[ \t]+(?=[\p{L}\p{N}])"#, options: []
    )
    private static let percentSpaceRegex = try? NSRegularExpression(
        pattern: #"(?<=\d)[ \t]+%"#, options: []
    )

    static func convertSpokenPunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = applyRomanAndNumberCommands(text)

        if let allCapsWordRegex {
            let matches = allCapsWordRegex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                guard let full = Range(match.range, in: result),
                      let wordRange = Range(match.range(at: 1), in: result)
                else { continue }
                result.replaceSubrange(full, with: result[wordRange].uppercased())
            }
        }

        for rule in compiledPunctuationRules {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = rule.regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.template)
        }

        // Collapse spaces around explicit spoken quotes, slashes, backslashes, underscores, and bullets
        result = result.replacingOccurrences(of: "\(quoteOpenMarker)[ \t]*", with: "\"", options: .regularExpression)
        result = result.replacingOccurrences(of: "[ \t]*\(quoteCloseMarker)", with: "\"", options: .regularExpression)
        result = result.replacingOccurrences(of: "\(singleQuoteOpenMarker)[ \t]*", with: "'", options: .regularExpression)
        result = result.replacingOccurrences(of: "[ \t]*\(singleQuoteCloseMarker)", with: "'", options: .regularExpression)
        result = result.replacingOccurrences(of: "[ \t]*\(slashMarker)[ \t]*", with: "/", options: .regularExpression)
        result = result.replacingOccurrences(of: "[ \t]*\(backslashMarker)[ \t]*", with: "\\\\", options: .regularExpression)
        result = result.replacingOccurrences(of: "[ \t]*\(underscoreMarker)[ \t]*", with: "_", options: .regularExpression)
        if result.contains(bulletMarker) {
            result = result.replacingOccurrences(of: #"(?<=[^\n])[ \t]*"# + bulletMarker + #"[ \t]*"#, with: "\n- ", options: .regularExpression)
            result = result.replacingOccurrences(of: bulletMarker + #"[ \t]*"#, with: "- ", options: .regularExpression)
        }

        result = applyDeterministicITN(result)
        return normalizePostPolishSymbols(result)
    }

    // MARK: - Deterministic ITN (Times, Versions, Percentages, Emails, Ratios)

    private static let percentWordRegex = try? NSRegularExpression(
        pattern: #"\b([a-zA-Z]+(?:\s+[a-zA-Z]+)?|\d+(?:\.\d+)?)\s+percent\b"#,
        options: [.caseInsensitive]
    )
    private static let versionRegex = try? NSRegularExpression(
        pattern: #"\bversion\s+([a-z0-9]+)\s+point\s+([a-z0-9]+)(?:\s+point\s+([a-z0-9]+))?\b"#,
        options: [.caseInsensitive]
    )
    private static let pointOhRegex = try? NSRegularExpression(
        pattern: #"\b(\d+|[a-z]+)\s+point\s+oh\b"#,
        options: [.caseInsensitive]
    )
    private static let timeAMPMRegex = try? NSRegularExpression(
        pattern: #"\b(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(oh\s+(?:one|two|three|four|five|six|seven|eight|nine|\d)|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|o'?clock|[0-5]\d)(?:\s+(five))?\s+(a\.?\s*m\.?|p\.?\s*m\.?)\b"#,
        options: [.caseInsensitive]
    )
    private static let spokenEmailRegex = try? NSRegularExpression(
        pattern: #"\b([a-z0-9._%+-]+(?:\s+dot\s+[a-z0-9._%+-]+)*)\s+at\s+([a-z0-9-]+(?:\s+dot\s+[a-z0-9-]+)*\s+dot\s+(?:com|org|net|io|dev|ai|edu|in|co|uk))\b"#,
        options: [.caseInsensitive]
    )
    private static let spokenTens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "hundred": 100
    ]

    static func applyDeterministicITN(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text

        // 1. Software versions: "version two point oh" / "version 1 point 2 point 3" -> "v2.0" / "v1.2.3"
        if let versionRegex {
            let matches = versionRegex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                guard let full = Range(match.range, in: result),
                      let r1 = Range(match.range(at: 1), in: result),
                      let r2 = Range(match.range(at: 2), in: result),
                      let v1 = parseSpokenSmallInt(String(result[r1])),
                      let v2 = parseSpokenVersionPart(String(result[r2]))
                else { continue }
                var formatted = "v\(v1).\(v2)"
                if match.range(at: 3).location != NSNotFound,
                   let r3 = Range(match.range(at: 3), in: result),
                   let v3 = parseSpokenVersionPart(String(result[r3])) {
                    formatted += ".\(v3)"
                }
                result.replaceSubrange(full, with: formatted)
            }
        }

        // 2. Ambiguous "point oh" -> ".0" (e.g. "three point oh" -> "3.0")
        if let pointOhRegex {
            let matches = pointOhRegex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                guard let full = Range(match.range, in: result),
                      let r1 = Range(match.range(at: 1), in: result),
                      let val = parseSpokenSmallInt(String(result[r1]))
                else { continue }
                result.replaceSubrange(full, with: "\(val).0")
            }
        }

        // 3. Spoken clock times: "three fifteen pm" -> "3:15 PM"
        if let timeAMPMRegex {
            let matches = timeAMPMRegex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                guard let full = Range(match.range, in: result),
                      let hrRange = Range(match.range(at: 1), in: result),
                      let minRange = Range(match.range(at: 2), in: result),
                      let ampmRange = Range(match.range(at: 4), in: result),
                      let hour = parseSpokenSmallInt(String(result[hrRange])), (1...12).contains(hour)
                else { continue }
                let minuteStr = String(result[minRange]).lowercased().trimmingCharacters(in: .whitespaces)
                let minutes: Int?
                if minuteStr == "o'clock" || minuteStr == "oclock" {
                    minutes = 0
                } else if minuteStr.hasPrefix("oh ") {
                    let tail = String(minuteStr.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    minutes = parseSpokenSmallInt(tail)
                } else if let mVal = parseSpokenSmallInt(minuteStr) {
                    if match.range(at: 3).location != NSNotFound,
                       let onesRange = Range(match.range(at: 3), in: result),
                       let ones = parseSpokenSmallInt(String(result[onesRange])) {
                        minutes = mVal + ones
                    } else {
                        minutes = mVal
                    }
                } else {
                    minutes = Int(minuteStr)
                }
                guard let m = minutes, (0...59).contains(m) else { continue }
                let mer = String(result[ampmRange]).lowercased().contains("p") ? "PM" : "AM"
                result.replaceSubrange(full, with: String(format: "%d:%02d %@", hour, m, mer))
            }
        }

        // 4. Spoken percentages: "forty five percent" -> "45%"
        if let percentWordRegex {
            let matches = percentWordRegex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                guard let full = Range(match.range, in: result),
                      let numRange = Range(match.range(at: 1), in: result)
                else { continue }
                let rawNum = String(result[numRange])
                if Double(rawNum) != nil {
                    result.replaceSubrange(full, with: "\(rawNum)%")
                } else if let n = parseCompoundNumber(rawNum) {
                    result.replaceSubrange(full, with: "\(n)%")
                }
            }
        }

        // 5. Spoken email addresses: "john dot doe at gmail dot com" -> "john.doe@gmail.com"
        if let spokenEmailRegex {
            let matches = spokenEmailRegex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                guard let full = Range(match.range, in: result),
                      let localR = Range(match.range(at: 1), in: result),
                      let domR = Range(match.range(at: 2), in: result)
                else { continue }
                let local = String(result[localR])
                    .replacingOccurrences(of: #"\s+dot\s+"#, with: ".", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased()
                let dom = String(result[domR])
                    .replacingOccurrences(of: #"\s+dot\s+"#, with: ".", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased()
                result.replaceSubrange(full, with: "\(local)@\(dom)")
            }
        }

        return result
    }

    private static func parseSpokenVersionPart(_ token: String) -> Int? {
        let lower = token.lowercased()
        if lower == "oh" || lower == "zero" { return 0 }
        return parseSpokenSmallInt(lower)
    }

    private static func parseSpokenSmallInt(_ token: String) -> Int? {
        let lower = token.lowercased().trimmingCharacters(in: .whitespaces)
        if let v = numberWords[lower] { return v }
        if let t = spokenTens[lower] { return t }
        return Int(lower)
    }

    private static func parseCompoundNumber(_ raw: String) -> Int? {
        let parts = raw.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return nil }
        if parts.count == 1 { return parseSpokenSmallInt(parts[0]) }
        if parts.count == 2, let tens = spokenTens[parts[0]], let ones = numberWords[parts[1]], (0...9).contains(ones) {
            return tens + ones
        }
        return nil
    }

    /// Cleans bracket/slash/punctuation spacing deterministically before or after LLM cleanup.
    static func normalizePostPolishSymbols(_ text: String) -> String {
        var result = text
        if let regex = commaInsideBracketRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        if let regex = commaBeforeClosingBracketRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        if let regex = spaceBeforePunctRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        if let regex = spaceAfterBracketRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        if let regex = inlineSlashSpacingRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "/")
        }
        if let regex = prefixSymbolSpaceRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        if let regex = percentSpaceRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "%")
        }
        if let regex = missingSpaceAfterSentenceRegex {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$0 ")
        }
        return result
    }

    private static func applyRomanAndNumberCommands(_ text: String) -> String {
        var result = text
        if let regex = romanCommandRegex {
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                guard let full = Range(match.range, in: result),
                      let tokenRange = Range(match.range(at: 1), in: result),
                      let value = parseNumeralValue(String(result[tokenRange]), allowHomophones: true),
                      value >= 1, value < romanNumerals.count
                else { continue }
                result.replaceSubrange(full, with: romanNumerals[value])
            }
        }
        if let regex = columnCommandRegex {
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                guard let full = Range(match.range, in: result),
                      let tokenRange = Range(match.range(at: 1), in: result),
                      let value = parseNumeralValue(String(result[tokenRange]), allowHomophones: false),
                      value >= 1, value <= 12
                else { continue }
                result.replaceSubrange(full, with: "Column \(romanNumerals[value])")
            }
        }
        if let regex = arabicNumeralCommandRegex {
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                guard let full = Range(match.range, in: result),
                      let tokenRange = Range(match.range(at: 1), in: result),
                      let value = numberWords[String(result[tokenRange]).lowercased()] ?? Int(String(result[tokenRange]))
                else { continue }
                result.replaceSubrange(full, with: String(value))
            }
        }
        return result
    }

    private static func parseNumeralValue(_ rawToken: String, allowHomophones: Bool) -> Int? {
        let lower = rawToken.lowercased()
        if let n = numberWords[lower], n >= 1 { return n }
        if let r = romanValues[lower] { return r }
        if allowHomophones, let h = romanHomophones[lower] { return h }
        if let d = Int(lower), d >= 1, d < romanNumerals.count { return d }
        return nil
    }

    // MARK: - Auto-Lists & Trailing Submit Commands

    private static let trailingSubmitRegex = try? NSRegularExpression(
        pattern: #"(?i)(?:[,.\s]+|^)(press\s+enter|hit\s+enter|hit\s+return|send\s+message)[.!?]*$"#,
        options: []
    )
    private static let negativeSubmitPrefixRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(?:don'?t|do\s+not|never|not\s+to)\s+$"#,
        options: []
    )

    /// Extracts trailing voice-submit command ("press enter" / "send message") safely.
    static func extractTrailingSubmitCommand(_ text: String) -> (text: String, shouldSubmit: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let regex = trailingSubmitRegex,
              let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
              let fullRange = Range(match.range, in: trimmed),
              let cmdRange = Range(match.range(at: 1), in: trimmed)
        else { return (text, false) }

        let prefix = String(trimmed[..<cmdRange.lowerBound])
        if let neg = negativeSubmitPrefixRegex,
           neg.firstMatch(in: prefix, options: [], range: NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)) != nil {
            return (text, false)
        }
        let cleaned = String(trimmed[..<fullRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return (text, false) }
        return (cleaned, true)
    }

    private static let ordinalItemMarkers: [(regex: NSRegularExpression, index: Int)] = {
        let pairs: [(String, Int)] = [
            (#"(?i)(?:^|[.!?\n;:,]\s+)(\b(?:first(?:ly)?|number\s+one|step\s+one|point\s+one)\b[,:\s]+)"#, 1),
            (#"(?i)(?:^|[.!?\n;:,]\s+)(\b(?:second(?:ly)?|number\s+two|step\s+two|point\s+two)\b[,:\s]+)"#, 2),
            (#"(?i)(?:^|[.!?\n;:,]\s+)(\b(?:third(?:ly)?|number\s+three|step\s+three|point\s+three)\b[,:\s]+)"#, 3),
            (#"(?i)(?:^|[.!?\n;:,]\s+)(\b(?:fourth(?:ly)?|number\s+four|step\s+four|point\s+four)\b[,:\s]+)"#, 4),
            (#"(?i)(?:^|[.!?\n;:,]\s+)(\b(?:fifth(?:ly)?|number\s+five|step\s+five|point\s+five)\b[,:\s]+)"#, 5)
        ]
        return pairs.compactMap { pattern, idx in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                assertionFailure("Invalid ordinal marker regex: \(pattern)")
                return nil
            }
            return (regex, idx)
        }
    }()

    /// Formats 2+ sequential spoken enumeration markers ("First ... Second ...") into numbered list lines.
    static func formatSpokenEnumerations(_ text: String) -> String {
        guard !text.isEmpty, !text.contains("\n- "), !text.contains("\n1. ") else { return text }
        var hits: [(index: Int, range: Range<String.Index>)] = []
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for (idx, item) in ordinalItemMarkers.enumerated() {
            if let m = item.regex.firstMatch(in: text, options: [], range: nsRange),
               let r = Range(m.range(at: 1), in: text) {
                if let last = hits.last, r.lowerBound <= last.range.upperBound { continue }
                if idx == 0 || !hits.isEmpty {
                    hits.append((item.index, r))
                }
            }
        }
        guard hits.count >= 2, hits[0].index == 1 else { return text }
        // Require strictly sequential indices (e.g. 1, 2 or 1, 2, 3)
        for offset in 1..<hits.count where hits[offset].index != hits[offset - 1].index + 1 {
            return text
        }

        var output = String(text[..<hits[0].range.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        if !output.isEmpty && !output.hasSuffix("\n") {
            output += "\n"
        }

        for i in 0..<hits.count {
            let start = hits[i].range.upperBound
            let end = i + 1 < hits.count ? hits[i + 1].range.lowerBound : text.endIndex
            var body = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if body.hasSuffix(",") || body.hasSuffix(";") {
                body.removeLast()
            }
            if let firstLetter = body.firstIndex(where: \.isLetter) {
                body.replaceSubrange(firstLetter...firstLetter, with: String(body[firstLetter]).uppercased())
            }
            if !body.isEmpty {
                output += "\(hits[i].index). \(body)"
                if i + 1 < hits.count { output += "\n" }
            }
        }
        return output
    }

    // MARK: - Filler Words Removal

    private static let fillerRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(?:^|\s*)((?:\b(?:um|umm|uh|uhh|hmm|mhm|mmm|er)\b)|(?:(?<![0-9])(?<![0-9] )(?<![0-9]-)\b(?:mm|ah)\b))[-.,!?…:;—]*(?=\s|$)"#,
            options: [.caseInsensitive]
        )
    }()
    private static let phraseFillerRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(?:(?:^|,\s*)\b(?:you\s+know)\b\s*,\s*|,\s*\b(?:you\s+know)\b(?=[.!?\s]|$))"#,
            options: [.caseInsensitive]
        )
    }()

    // MARK: - Backtracking & Speech Repair (Clause / Sentence Scoped)

    private static let backtrackPatterns: [String] = [
        #"(?i)^[^\n.!?]+?[,\s]+(?:actually\s+make\s+that|actually\s+wait|actually\s+no|actually)[,\s]+(.+)$"#,
        #"(?i)^[^\n.!?]+?[,\s]+(?:no\s+wait|wait\s+no|wait\s+sorry|sorry\s+no)[,\s]+(.+)$"#,
        #"(?i)^[^\n.!?]+?[,\s]+(?:scratch\s+that)[,\s]+(.+)$"#,
        #"(?i)^[^\n.!?]+?[,\s]+(?:sorry\s+I\s+mean|I\s+mean)[,\s]+(.+)$"#,
        #"(?i)^[^\n.!?]+?[,\s]+(?:or\s+rather)[,\s]+(.+)$"#
    ]

    private static let compiledBacktrackRegexes: [NSRegularExpression] = {
        backtrackPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    /// Resolves mid-sentence corrections inside each individual sentence/clause boundary
    /// so earlier completed sentences remain completely intact.
    static func resolveBacktracks(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let segmentRegex = try? NSRegularExpression(pattern: #"[^\n.!?]+(?:[.!?]+|$)|\n+"#, options: [])
        guard let segmentRegex else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let segments = segmentRegex.matches(in: text, options: [], range: nsRange)
        guard !segments.isEmpty else { return text }

        var output = ""
        for segMatch in segments {
            guard let range = Range(segMatch.range, in: text) else { continue }
            let piece = String(text[range])
            let leadingWS = String(piece.prefix(while: { $0 == " " || $0 == "\t" }))
            var trimmedPiece = piece.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if !trimmedPiece.isEmpty && !trimmedPiece.hasPrefix("\n") {
                for regex in compiledBacktrackRegexes {
                    let r = NSRange(trimmedPiece.startIndex..<trimmedPiece.endIndex, in: trimmedPiece)
                    if regex.firstMatch(in: trimmedPiece, options: [], range: r) != nil {
                        trimmedPiece = regex.stringByReplacingMatches(in: trimmedPiece, options: [], range: r, withTemplate: "$1")
                    }
                }
                output += leadingWS + trimmedPiece.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            } else {
                output += piece
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func removeFillerWords(_ text: String) -> String {
        var working = text
        if let phraseFillerRegex {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            working = phraseFillerRegex.stringByReplacingMatches(in: working, options: [], range: range, withTemplate: " ")
        }
        guard let regex = fillerRegex else { return working }
        let range = NSRange(working.startIndex..<working.endIndex, in: working)
        let cleaned = regex.stringByReplacingMatches(in: working, options: [], range: range, withTemplate: "")
        // Normalize any collapsed double spaces
        return cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Repetition & Stutter Collapse

    private static let repetitionRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\b([a-zA-Z0-9']+)\s+\1\b"#,
            options: [.caseInsensitive]
        )
    }()
    private static let stutterPrefixRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\b([a-zA-Z]{1,2})-(?=\1[a-zA-Z])"#,
            options: [.caseInsensitive]
        )
    }()

    static func collapseRepetitions(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        if let stutterPrefixRegex {
            for _ in 0..<3 {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                guard stutterPrefixRegex.firstMatch(in: result, options: [], range: range) != nil else { break }
                result = stutterPrefixRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        guard let regex = repetitionRegex else { return result }
        var iterations = 0
        while iterations < 3 {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            guard !matches.isEmpty else { break }
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            iterations += 1
        }
        return result
    }

    // MARK: - ASR Hallucination & Loop Suppression

    private static let phantomCaptions: [String] = [
        "thank you for watching",
        "thanks for watching",
        "please subscribe",
        "like and subscribe",
        "subscribe to my channel",
        "subtitles by",
        "captioned by",
        "amara.org"
    ]

    /// Removes known phantom Whisper artifacts and collapses degenerate trailing clause loops.
    static func stripHallucinations(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let sentences = trimmed.split(omittingEmptySubsequences: true) { ".!?".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sentences.count >= 3, let last = sentences.last {
            let normLast = last.lowercased()
            let repeats = sentences.reversed().prefix(while: { $0.lowercased() == normLast }).count
            if repeats >= 3 {
                let keptCount = sentences.count - repeats + 1
                trimmed = sentences.prefix(keptCount).joined(separator: ". ") + "."
            }
        }

        let normalizedWhole = trimmed.lowercased()
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        if phantomCaptions.contains(where: { normalizedWhole == $0 || normalizedWhole.hasPrefix("subtitles by ") }) {
            return ""
        }

        for phantom in phantomCaptions {
            let escaped = NSRegularExpression.escapedPattern(for: phantom)
            let pattern = #"(?i)(?:(?<=[.!?])\s+|\s+)"# + escaped + #"[.!?…]*$"#
            trimmed = trimmed.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    // MARK: - Echo Stripping

    static func stripEcho(_ text: String, after previous: String) -> String {
        guard !text.isEmpty, !previous.isEmpty else { return text }
        let tail = Array(previous.split(separator: " ").suffix(8))
        let head = Array(text.split(separator: " "))
        let plain = { (word: Substring) in
            word.lowercased()
                .replacingOccurrences(of: "’", with: "'")
                .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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

    /// Checks whether the text ends with a sentence-terminating punctuation.
    static func endsWithSentenceTerminator(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let sentenceClosures = [
            ".", ".\"", ".'", ".’", ".)", ".]", ".}", "…",
            "!", "!\"", "!'", "!’", "!)", "!]",
            "?", "?\"", "?'", "?’", "?)"
        ]
        return sentenceClosures.contains { trimmed.hasSuffix($0) }
    }

    static func format(_ transcription: String, context: Context?, adaptCapitalization: Bool = true) -> String {
        var text = transcription.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // List/checkbox continuation awareness: avoid duplicate "- " or "1. " when already on a list line.
        if let context {
            let prefixTrim = context.currentLinePrefix.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if prefixTrim == "-" || prefixTrim == "*" || prefixTrim == "- [ ]" || prefixTrim == "- [x]" {
                if text.hasPrefix("- ") {
                    text = String(text.dropFirst(2))
                }
            } else if let match = prefixTrim.range(of: #"^\d+\.$"#, options: .regularExpression),
                      let currentNum = Int(prefixTrim[match].dropLast()),
                      text.hasPrefix("1. ")
            {
                text = String(text.dropFirst(3))
                var nextNum = currentNum + 1
                var lineIndex = 2
                while text.contains("\n\(lineIndex). ") {
                    text = text.replacingOccurrences(of: "\n\(lineIndex). ", with: "\n\(nextNum). ")
                    nextNum += 1
                    lineIndex += 1
                }
            }
        }

        let lowercasedMidSentence = adaptCapitalization && shouldLowercaseMidSentence(text: text, context: context)
        if lowercasedMidSentence, let firstLetterIndex = text.firstIndex(where: { $0.isLetter }) {
            let firstWord = text[firstLetterIndex...].prefix { $0.isLetter }
            let isAcronym = firstWord.count >= 2 && firstWord.allSatisfy(\.isUppercase)
            if firstWord != "I" && !isAcronym {
                text.replaceSubrange(firstLetterIndex...firstLetterIndex, with: String(text[firstLetterIndex]).lowercased())
            }
        } else if let firstLetterIndex = text.firstIndex(where: { $0.isLetter }) {
            text.replaceSubrange(firstLetterIndex...firstLetterIndex, with: String(text[firstLetterIndex]).uppercased())
        }

        let isSentenceEnding = endsWithSentenceTerminator(text)

        if let context {
            if let leading = context.following {
                // If following context already has whitespace or is closing punctuation, don't append space
                if !leading.isWhitespace && !".,!?;:)]}/\"'”".contains(leading) {
                    if isSentenceEnding || (text.last.map { !$0.isWhitespace } ?? false) {
                        text += " "
                    }
                }
            } else if isSentenceEnding {
                // End of document / caret at boundary: sentence full stop automatically gets a trailing space
                text += " "
            }
        } else if isSentenceEnding {
            // No context available (or external app): sentence full stop automatically gets a trailing space
            text += " "
        }

        return text
    }

    private static func shouldLowercaseMidSentence(text: String, context: Context?) -> Bool {
        guard let context, !context.newParagraph else { return false }
        let trimmedPrefix = context.currentLinePrefix
        if trimmedPrefix.hasSuffix("http://") || trimmedPrefix.hasSuffix("https://")
            || trimmedPrefix.hasSuffix("/") || trimmedPrefix.hasSuffix("@")
            || trimmedPrefix.hasSuffix("_") {
            return true
        }
        guard let last = context.lastNonWhitespace else { return false }
        if ".!?\n".contains(last) { return false }
        // Only lowercase after mid-clause separators (comma/semicolon) so existing caret word/paren insertion keeps expected casing.
        return last == "," || last == ";"
    }

    // MARK: - Code, Obsidian Markdown & Standalone Voice Meta-Commands

    private static let metaCommands: [(aliases: Set<String>, command: VoiceMetaCommand)] = [
        (["undo", "undo that", "undo last", "undo dictation", "undo last dictation"], .undoLast),
        (["select all", "highlight all"], .selectAll),
        (["copy that", "copy this"], .copyThat),
        (["new tab", "open new tab"], .newTab)
    ]

    /// Matches explicit standalone meta-commands (<= 4 words) without interfering with normal prose.
    static func extractVoiceMetaCommand(_ text: String) -> VoiceMetaCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
        guard !trimmed.isEmpty, trimmed.split(whereSeparator: \.isWhitespace).count <= 4 else { return nil }
        for entry in metaCommands where entry.aliases.contains(trimmed) {
            return entry.command
        }
        return nil
    }

    private static let askAIPrefixRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(?is)^(?:ask\s+ai|hey\s+ai|ask\s+assistant)(?:[:,\s]+(.+))$"#,
            options: []
        )
    }()

    /// Extracts an explicit "Ask AI ..." / "Hey AI ..." voice query when spoken at the start of a clip.
    static func extractAskAIQuery(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let askAIPrefixRegex else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = askAIPrefixRegex.firstMatch(in: trimmed, options: [], range: range),
              let qRange = Range(match.range(at: 1), in: trimmed)
        else { return nil }
        let query = String(trimmed[qRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = query.split(whereSeparator: \.isWhitespace).count
        guard query.count >= 6 || wordCount >= 2 else { return nil }
        return query
    }

    /// Strips the first `(|)` or `{cursor}` caret marker from expanded dictation text and returns offset from end.
    static func extractCursorMarker(from text: String) -> (text: String, cursorOffsetFromEnd: Int?) {
        for marker in ["(|)", "{cursor}"] {
            if let range = text.range(of: marker) {
                var stripped = text
                stripped.removeSubrange(range)
                let afterCount = text[range.upperBound...].count
                return (stripped, afterCount > 0 ? afterCount : nil)
            }
        }
        return (text, nil)
    }

    /// Formats developer case conventions, Markdown/Obsidian syntax, and CLI path shorthands cleanly.
    static func formatSyntaxCommands(_ text: String, isCodeContext: Bool, isNotesContext: Bool) -> String {
        guard !text.isEmpty else { return text }
        var result = text

        if isNotesContext || isCodeContext {
            let mdPatterns: [(String, (NSTextCheckingResult, String) -> String?)] = [
                (#"(?im)^heading\s+(?:one|1)[:,\s]+([^\n]+)$"#, { m, s in
                    guard let r = Range(m.range(at: 1), in: s) else { return nil }
                    return "# " + String(s[r]).trimmingCharacters(in: .whitespaces)
                }),
                (#"(?im)^heading\s+(?:two|2)[:,\s]+([^\n]+)$"#, { m, s in
                    guard let r = Range(m.range(at: 1), in: s) else { return nil }
                    return "## " + String(s[r]).trimmingCharacters(in: .whitespaces)
                }),
                (#"(?im)^heading\s+(?:three|3)[:,\s]+([^\n]+)$"#, { m, s in
                    guard let r = Range(m.range(at: 1), in: s) else { return nil }
                    return "### " + String(s[r]).trimmingCharacters(in: .whitespaces)
                }),
                (#"(?i)\b(?:task\s+item|todo\s+item)[:,\s]+([^\n.!?]+)"#, { m, s in
                    guard let r = Range(m.range(at: 1), in: s) else { return nil }
                    return "- [ ] " + String(s[r]).trimmingCharacters(in: .whitespaces)
                }),
                (#"(?i)\bwiki\s*link\s+([A-Za-z0-9 _-]+?)(?=[.,!?\n]|$)"#, { m, s in
                    guard let r = Range(m.range(at: 1), in: s) else { return nil }
                    return "[[" + String(s[r]).trimmingCharacters(in: .whitespaces) + "]]"
                })
            ]
            for (pattern, builder) in mdPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
                    for match in matches.reversed() {
                        if let full = Range(match.range, in: result), let rep = builder(match, result) {
                            result.replaceSubrange(full, with: rep)
                        }
                    }
                }
            }
        }

        if isCodeContext {
            // 1. Convert operators, paths, and CLI flags before identifier casing so they act as natural boundaries.
            let codeSymbols: [(String, String)] = [
                (#"\b(?:fat\s+arrow|lambda\s+arrow)\b"#, "=>"),
                (#"\b(?:thin\s+arrow|return\s+arrow)\b"#, "->"),
                (#"\btriple\s+equals\b"#, "==="),
                (#"\bdouble\s+equals\b"#, "=="),
                (#"\bnot\s+equals\b"#, "!="),
                (#"\bdot\s+env\b"#, ".env"),
                (#"\btilde\s+slash\s*"#, "~/")
            ]
            for (pat, rep) in codeSymbols {
                result = result.replacingOccurrences(of: pat, with: rep, options: [.regularExpression, .caseInsensitive])
            }
            if let flagRegex = try? NSRegularExpression(pattern: #"(?i)\bdash\s+dash\s+([a-z0-9-]+)\b"#) {
                let matches = flagRegex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
                for m in matches.reversed() {
                    if let full = Range(m.range, in: result), let r1 = Range(m.range(at: 1), in: result) {
                        result.replaceSubrange(full, with: "--" + result[r1].lowercased())
                    }
                }
            }

            // 2. Format identifier casing without swallowing conjunctions, paths, or chained casing directives.
            let identifierTransform: (String, String) -> String = { kind, rawPhrase in
                let words = rawPhrase.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
                guard !words.isEmpty else { return rawPhrase }
                switch kind {
                case "camel":
                    return words.enumerated().map { idx, w in idx == 0 ? w : w.capitalized }.joined()
                case "pascal":
                    return words.map(\.capitalized).joined()
                case "snake":
                    return words.joined(separator: "_")
                case "kebab":
                    return words.joined(separator: "-")
                case "constant", "screaming snake":
                    return words.map { $0.uppercased() }.joined(separator: "_")
                default:
                    return rawPhrase
                }
            }
            let wordToken = #"(?!(?:camel|pascal|snake|kebab|constant|screaming\s+snake)\s+case\b)(?!(?:and|or|then|while|when|where|because)\b)(?!in\s+(?:the|a|an|[~\./=<>!-]))[a-z0-9]+"#
            if let regex = try? NSRegularExpression(
                pattern: #"(?i)\b(camel|pascal|snake|kebab|constant|screaming\s+snake)\s+case\s+("# + wordToken + #"(?:\s+"# + wordToken + #"){0,4})\b"#,
                options: []
            ) {
                let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
                for match in matches.reversed() {
                    guard let full = Range(match.range, in: result),
                          let kindR = Range(match.range(at: 1), in: result),
                          let wordsR = Range(match.range(at: 2), in: result)
                    else { continue }
                    let kind = String(result[kindR]).lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    result.replaceSubrange(full, with: identifierTransform(kind, String(result[wordsR])))
                }
            }
        }
        return result
    }
}
