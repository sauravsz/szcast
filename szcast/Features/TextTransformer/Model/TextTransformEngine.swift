import Foundation

enum TextTransformEngine: Sendable {
    static func transform(_ text: String, using type: TextTransformType) -> String {
        switch type {
        // Casing
        case .camelCase:
            let words = extractWords(from: text)
            guard let first = words.first else { return "" }
            let tail = words.dropFirst().map { $0.capitalized }
            return ([first.lowercased()] + tail).joined()

        case .pascalCase:
            let words = extractWords(from: text)
            return words.map { $0.capitalized }.joined()

        case .snakeCase:
            let words = extractWords(from: text)
            return words.map { $0.lowercased() }.joined(separator: "_")

        case .kebabCase:
            let words = extractWords(from: text)
            return words.map { $0.lowercased() }.joined(separator: "-")

        case .constantCase:
            let words = extractWords(from: text)
            return words.map { $0.uppercased() }.joined(separator: "_")

        case .titleCase:
            let words = extractWords(from: text)
            return words.map { $0.capitalized }.joined(separator: " ")

        case .sentenceCase:
            return toSentenceCase(text)

        case .lowercase:
            return text.lowercased()

        case .uppercase:
            return text.uppercased()

        case .alternatingCase:
            var uppercase = true
            return String(text.map { char in
                guard char.isLetter else { return char }
                uppercase.toggle()
                return uppercase ? Character(char.uppercased()) : Character(char.lowercased())
            })

        // Lines
        case .sortAZ:
            let lines = text.components(separatedBy: .newlines)
            return lines.sorted().joined(separator: "\n")

        case .sortZA:
            let lines = text.components(separatedBy: .newlines)
            return lines.sorted(by: >).joined(separator: "\n")

        case .deduplicate:
            var seen = Set<String>()
            var unique: [String] = []
            for line in text.components(separatedBy: .newlines) {
                if !seen.contains(line) {
                    seen.insert(line)
                    unique.append(line)
                }
            }
            return unique.joined(separator: "\n")

        case .reverseLines:
            let lines = text.components(separatedBy: .newlines)
            return lines.reversed().joined(separator: "\n")

        case .stripBlankLines:
            let lines = text.components(separatedBy: .newlines)
            let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return nonBlank.joined(separator: "\n")

        case .numberLines:
            let lines = text.components(separatedBy: .newlines)
            var numbered: [String] = []
            for (index, line) in lines.enumerated() {
                numbered.append("\(index + 1). \(line)")
            }
            return numbered.joined(separator: "\n")

        case .trimLines:
            let lines = text.components(separatedBy: .newlines)
            return lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")

        case .joinLines:
            let lines = text.components(separatedBy: .newlines)
            let filtered = lines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return filtered.joined(separator: " ")

        // Encoding
        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text

        case .urlDecode:
            return text.removingPercentEncoding ?? text

        case .base64Encode:
            return Data(text.utf8).base64EncodedString()

        case .base64Decode:
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: clean),
                  let decoded = String(data: data, encoding: .utf8) else {
                return text
            }
            return decoded

        case .htmlEntityEncode:
            return text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")

        case .htmlEntityDecode:
            return text
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&nbsp;", with: " ")

        case .hexEncode:
            return text.utf8.map { String(format: "%02x", $0) }.joined()

        case .hexDecode:
            let clean = text.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "0x", with: "")
            guard clean.count % 2 == 0 else { return text }
            var data = Data()
            var index = clean.startIndex
            while index < clean.endIndex {
                let nextIndex = clean.index(index, offsetBy: 2)
                let byteString = clean[index..<nextIndex]
                guard let byte = UInt8(byteString, radix: 16) else { return text }
                data.append(byte)
                index = nextIndex
            }
            return String(data: data, encoding: .utf8) ?? text

        // Formatting
        case .jsonPrettify:
            guard let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: []),
                  let formatted = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                  let str = String(data: formatted, encoding: .utf8) else {
                return text
            }
            return str

        case .jsonMinify:
            guard let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: []),
                  let formatted = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
                  let str = String(data: formatted, encoding: .utf8) else {
                return text
            }
            return str

        case .stripTrackingURL:
            let sanitized = URLSanitizer.sanitize(text)
            return sanitized.cleanURL

        case .stripMarkdown:
            return stripMarkdownSyntax(from: text)

        case .stripHTML:
            return stripHTMLTags(from: text)

        case .normalizeWhitespace:
            let lines = text.components(separatedBy: .newlines)
            let cleanedLines = lines.map { line -> String in
                line.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            return cleanedLines.joined(separator: "\n")

        case .slugify:
            let words = extractWords(from: text)
            let slug = words.map { $0.lowercased() }.joined(separator: "-")
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
            return slug.unicodeScalars.filter { allowed.contains($0) }.map { String($0) }.joined()
        }
    }

    // MARK: - Helpers

    static func extractWords(from text: String) -> [String] {
        var words: [String] = []
        var currentWord = ""

        func flush() {
            let trimmed = currentWord.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                words.append(trimmed)
            }
            currentWord = ""
        }

        let chars = Array(text)
        for i in 0..<chars.count {
            let ch = chars[i]
            if ch.isLetter || ch.isNumber {
                if ch.isUppercase && !currentWord.isEmpty {
                    let prev = chars[i - 1]
                    let next = (i + 1 < chars.count) ? chars[i + 1] : nil

                    // Split on camelCase (e.g. prev lowercase, current uppercase)
                    if prev.isLowercase {
                        flush()
                    }
                    // Split on acronym end (e.g. "XMLParser" -> prev uppercase, next lowercase)
                    else if prev.isUppercase && (next?.isLowercase ?? false) {
                        flush()
                    }
                }
                currentWord.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return words
    }

    private static func toSentenceCase(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true

        for ch in text {
            if ch.isLetter {
                if capitalizeNext {
                    result.append(Character(ch.uppercased()))
                    capitalizeNext = false
                } else {
                    result.append(Character(ch.lowercased()))
                }
            } else {
                result.append(ch)
                if ch == "." || ch == "!" || ch == "?" {
                    capitalizeNext = true
                }
            }
        }
        return result
    }

    private static func stripMarkdownSyntax(from text: String) -> String {
        var str = text
        // Strip images ![alt](url) -> ""
        if let regex = try? NSRegularExpression(pattern: #"!\[.*?\]\(.*?\)"#) {
            str = regex.stringByReplacingMatches(in: str, range: NSRange(str.startIndex..., in: str), withTemplate: "")
        }
        // Strip links [text](url) -> text
        if let regex = try? NSRegularExpression(pattern: #"\[(.*?)\]\(.*?\)"#) {
            str = regex.stringByReplacingMatches(in: str, range: NSRange(str.startIndex..., in: str), withTemplate: "$1")
        }
        // Strip bold/italics (***, **, *, __, _)
        str = str.replacingOccurrences(of: "***", with: "")
            .replacingOccurrences(of: "___", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")

        // Strip heading markers "# " at line starts
        let lines = str.components(separatedBy: .newlines).map { line -> String in
            var l = line.trimmingCharacters(in: .whitespaces)
            while l.hasPrefix("#") {
                l.removeFirst()
            }
            return l.trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n")
    }

    private static func stripHTMLTags(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
}
