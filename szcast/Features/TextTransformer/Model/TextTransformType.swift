import Foundation

enum TransformCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case casing = "casing"
    case lines = "lines"
    case encoding = "encoding"
    case formatting = "formatting"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .casing: return String(localized: "Casing")
        case .lines: return String(localized: "Lines")
        case .encoding: return String(localized: "Encoding")
        case .formatting: return String(localized: "Formatting")
        }
    }

    var sfSymbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .casing: return "textformat"
        case .lines: return "list.bullet"
        case .encoding: return "lock.rectangle"
        case .formatting: return "wand.and.stars"
        }
    }
}

enum TextTransformType: String, CaseIterable, Identifiable, Sendable {
    // Casing
    case camelCase = "camel-case"
    case pascalCase = "pascal-case"
    case snakeCase = "snake-case"
    case kebabCase = "kebab-case"
    case constantCase = "constant-case"
    case titleCase = "title-case"
    case sentenceCase = "sentence-case"
    case lowercase = "lowercase"
    case uppercase = "uppercase"
    case alternatingCase = "alternating-case"

    // Lines
    case sortAZ = "sort-az"
    case sortZA = "sort-za"
    case deduplicate = "deduplicate"
    case reverseLines = "reverse-lines"
    case stripBlankLines = "strip-blank-lines"
    case numberLines = "number-lines"
    case trimLines = "trim-lines"
    case joinLines = "join-lines"

    // Encoding
    case urlEncode = "url-encode"
    case urlDecode = "url-decode"
    case base64Encode = "base64-encode"
    case base64Decode = "base64-decode"
    case htmlEntityEncode = "html-encode"
    case htmlEntityDecode = "html-decode"
    case hexEncode = "hex-encode"
    case hexDecode = "hex-decode"

    // Formatting
    case jsonPrettify = "json-prettify"
    case jsonMinify = "json-minify"
    case stripTrackingURL = "strip-tracking-url"
    case stripMarkdown = "strip-markdown"
    case stripHTML = "strip-html"
    case normalizeWhitespace = "normalize-whitespace"
    case slugify = "slugify"

    var id: String { rawValue }

    var category: TransformCategory {
        switch self {
        case .camelCase, .pascalCase, .snakeCase, .kebabCase, .constantCase,
             .titleCase, .sentenceCase, .lowercase, .uppercase, .alternatingCase:
            return .casing

        case .sortAZ, .sortZA, .deduplicate, .reverseLines,
             .stripBlankLines, .numberLines, .trimLines, .joinLines:
            return .lines

        case .urlEncode, .urlDecode, .base64Encode, .base64Decode,
             .htmlEntityEncode, .htmlEntityDecode, .hexEncode, .hexDecode:
            return .encoding

        case .jsonPrettify, .jsonMinify, .stripTrackingURL,
             .stripMarkdown, .stripHTML, .normalizeWhitespace, .slugify:
            return .formatting
        }
    }

    var title: String {
        switch self {
        case .camelCase: return String(localized: "camelCase")
        case .pascalCase: return String(localized: "PascalCase")
        case .snakeCase: return String(localized: "snake_case")
        case .kebabCase: return String(localized: "kebab-case")
        case .constantCase: return String(localized: "CONSTANT_CASE")
        case .titleCase: return String(localized: "Title Case")
        case .sentenceCase: return String(localized: "Sentence case")
        case .lowercase: return String(localized: "lower case")
        case .uppercase: return String(localized: "UPPER CASE")
        case .alternatingCase: return String(localized: "aLtErNaTiNg cAsE")

        case .sortAZ: return String(localized: "Sort Lines (A to Z)")
        case .sortZA: return String(localized: "Sort Lines (Z to A)")
        case .deduplicate: return String(localized: "Remove Duplicate Lines")
        case .reverseLines: return String(localized: "Reverse Lines")
        case .stripBlankLines: return String(localized: "Remove Blank Lines")
        case .numberLines: return String(localized: "Number Lines")
        case .trimLines: return String(localized: "Trim Line Whitespace")
        case .joinLines: return String(localized: "Join Lines with Space")

        case .urlEncode: return String(localized: "URL Encode")
        case .urlDecode: return String(localized: "URL Decode")
        case .base64Encode: return String(localized: "Base64 Encode")
        case .base64Decode: return String(localized: "Base64 Decode")
        case .htmlEntityEncode: return String(localized: "HTML Entity Encode")
        case .htmlEntityDecode: return String(localized: "HTML Entity Decode")
        case .hexEncode: return String(localized: "Hex Encode")
        case .hexDecode: return String(localized: "Hex Decode")

        case .jsonPrettify: return String(localized: "JSON Prettify")
        case .jsonMinify: return String(localized: "JSON Minify")
        case .stripTrackingURL: return String(localized: "Clean Tracking URL")
        case .stripMarkdown: return String(localized: "Strip Markdown Syntax")
        case .stripHTML: return String(localized: "Strip HTML Tags")
        case .normalizeWhitespace: return String(localized: "Normalize Whitespace")
        case .slugify: return String(localized: "Generate URL Slug")
        }
    }

    var subtitle: String {
        switch self {
        case .camelCase: return String(localized: "lowerCamelCase representation")
        case .pascalCase: return String(localized: "UpperCamelCase representation")
        case .snakeCase: return String(localized: "Words separated by underscores")
        case .kebabCase: return String(localized: "Words separated by hyphens")
        case .constantCase: return String(localized: "UPPERCASE words joined by underscores")
        case .titleCase: return String(localized: "Capitalize first letter of each word")
        case .sentenceCase: return String(localized: "Capitalize first character of sentences")
        case .lowercase: return String(localized: "Convert all characters to lowercase")
        case .uppercase: return String(localized: "Convert all characters to uppercase")
        case .alternatingCase: return String(localized: "Alternate upper and lowercase characters")

        case .sortAZ: return String(localized: "Sort lines in alphabetical order")
        case .sortZA: return String(localized: "Sort lines in reverse alphabetical order")
        case .deduplicate: return String(localized: "Remove duplicate lines preserving order")
        case .reverseLines: return String(localized: "Reverse order of lines bottom-to-top")
        case .stripBlankLines: return String(localized: "Filter out empty or whitespace-only lines")
        case .numberLines: return String(localized: "Prefix each line with 1., 2., etc.")
        case .trimLines: return String(localized: "Remove leading and trailing whitespace on each line")
        case .joinLines: return String(localized: "Collapse multiple lines into a single sentence")

        case .urlEncode: return String(localized: "Percent-encode URL query components")
        case .urlDecode: return String(localized: "Decode percent-encoded URL characters")
        case .base64Encode: return String(localized: "Encode UTF-8 string to Base64")
        case .base64Decode: return String(localized: "Decode Base64 payload to text")
        case .htmlEntityEncode: return String(localized: "Escape &, <, >, \", and ' into HTML entities")
        case .htmlEntityDecode: return String(localized: "Convert HTML entities back to characters")
        case .hexEncode: return String(localized: "Convert string to hexadecimal byte pairs")
        case .hexDecode: return String(localized: "Decode hexadecimal byte pairs back to string")

        case .jsonPrettify: return String(localized: "Format JSON with 2-space indentation and sorted keys")
        case .jsonMinify: return String(localized: "Compact JSON removing whitespace")
        case .stripTrackingURL: return String(localized: "Strip UTM, analytics, and marketing query parameters")
        case .stripMarkdown: return String(localized: "Extract plain prose removing markdown formatting")
        case .stripHTML: return String(localized: "Remove all HTML tags preserving inner text")
        case .normalizeWhitespace: return String(localized: "Collapse consecutive spaces and tabs into single space")
        case .slugify: return String(localized: "Convert text to clean, URL-safe hyphenated slug")
        }
    }

    var sfSymbol: String {
        switch self {
        case .camelCase, .pascalCase: return "textformat"
        case .snakeCase, .kebabCase, .constantCase: return "character.cursor.ibeam"
        case .titleCase, .sentenceCase: return "textformat.size"
        case .lowercase: return "textformat.characters.arrow.left"
        case .uppercase: return "textformat.characters.arrow.right"
        case .alternatingCase: return "waveform.path"

        case .sortAZ: return "arrow.up.and.down.text.horizontal"
        case .sortZA: return "arrow.down.and.up.text.horizontal"
        case .deduplicate: return "line.3.horizontal.decrease.circle"
        case .reverseLines: return "arrow.triangle.swap"
        case .stripBlankLines: return "rectangle.compress.vertical"
        case .numberLines: return "list.number"
        case .trimLines: return "scissors"
        case .joinLines: return "text.badge.minus"

        case .urlEncode, .urlDecode: return "link"
        case .base64Encode, .base64Decode: return "lock.rectangle"
        case .htmlEntityEncode, .htmlEntityDecode: return "chevron.left.forwardslash.chevron.right"
        case .hexEncode, .hexDecode: return "number"

        case .jsonPrettify: return "curlybraces"
        case .jsonMinify: return "arrow.right.to.line.compact"
        case .stripTrackingURL: return "shield.checkered"
        case .stripMarkdown: return "doc.plaintext"
        case .stripHTML: return "safari"
        case .normalizeWhitespace: return "space"
        case .slugify: return "link.badge.plus"
        }
    }
}

struct TextMetrics: Equatable, Sendable {
    let characters: Int
    let words: Int
    let lines: Int
    let bytes: Int

    static let zero = TextMetrics(characters: 0, words: 0, lines: 0, bytes: 0)

    init(text: String) {
        characters = text.count
        bytes = text.utf8.count
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            words = 0
            lines = text.isEmpty ? 0 : 1
        } else {
            words = text.split { $0.isWhitespace || $0.isPunctuation }.count
            let lineSeparators = CharacterSet.newlines
            lines = text.components(separatedBy: lineSeparators).count
        }
    }

    init(characters: Int, words: Int, lines: Int, bytes: Int) {
        self.characters = characters
        self.words = words
        self.lines = lines
        self.bytes = bytes
    }
}
