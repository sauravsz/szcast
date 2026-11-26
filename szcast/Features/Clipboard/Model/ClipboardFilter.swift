import Foundation

enum ClipboardFilter: CaseIterable, Sendable {
    case all
    case text
    case image
    case file
    case color
    case link
    case email

    var title: String {
        switch self {
        case .all: return String(localized: "All Types")
        case .text: return String(localized: "Text Only")
        case .image: return String(localized: "Images Only")
        case .file: return String(localized: "Files Only")
        case .color: return String(localized: "Colors Only")
        case .link: return String(localized: "Links Only")
        case .email: return String(localized: "Emails Only")
        }
    }

    /// Also the header button's glyph, so it states the active filter without opening the menu.
    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .text: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "eyedropper"
        case .link: return "link"
        case .email: return "at"
        }
    }

    /// What an empty list says, so a filter hiding every entry explains itself.
    var emptyMessage: String {
        switch self {
        case .all: return String(localized: "Clipboard history is empty")
        case .text: return String(localized: "No text in clipboard history")
        case .image: return String(localized: "No images in clipboard history")
        case .file: return String(localized: "No files in clipboard history")
        case .color: return String(localized: "No colors in clipboard history")
        case .link: return String(localized: "No links in clipboard history")
        case .email: return String(localized: "No email addresses in clipboard history")
        }
    }

    /// The kinds are exclusive: a copied URL is a link rather than a narrower kind of text.
    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .image: return item.kind == .image
        case .file: return item.kind == .file
        case .text: return item.textForm == .plain
        case .color: return item.textForm == .color
        case .link: return item.textForm == .link
        case .email: return item.textForm == .email
        }
    }

    /// Identity for `all`, so an unfiltered list never pays for a copy.
    func apply(to items: [ClipboardItem]) -> [ClipboardItem] {
        self == .all ? items : items.filter(matches)
    }
}

extension ClipboardItem {
    /// What a text entry holds; `Kind` says how an entry is stored, this says what it is.
    enum TextForm: Sendable {
        case plain
        case color
        case link
        case email
    }

    var colorValue: ColorValue? {
        guard kind == .text, let text else { return nil }
        return ColorValue.parse(text)
    }

    /// Derived and never persisted, so reclassifying is a code change rather than a migration.
    var textForm: TextForm? {
        guard kind == .text, let text else { return nil }
        return Self.classify(text)
    }

    /// A link or an address is one short token, so anything longer is prose by definition.
    /// Normalized HTTP(S) URL for copied web links (returns nil for plain text, emails, or custom schemes).
    var websiteURL: URL? {
        guard textForm == .link, let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        let normalized: String
        if raw.range(of: "://") == nil {
            normalized = "https://" + raw
        } else {
            normalized = raw
        }
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    private static let detectionLimit = 2048

    /// A scheme-less link needs a TLD people actually copy, or every `report.pdf` reads as one.
    private static let commonTopLevelDomains: Set<String> = [
        "com", "org", "net", "edu", "gov", "io", "co", "ai", "app", "dev", "me", "info", "biz",
        "xyz", "tv", "ly", "gg", "to", "uk", "us", "eu", "de", "fr", "es", "it", "nl", "se", "no",
        "fi", "dk", "ch", "at", "be", "ie", "cz", "ru", "ua", "tr", "cn", "jp", "kr", "hk", "sg",
        "au", "nz", "ca", "mx", "br", "ar", "za"
    ]

    private static func classify(_ text: String) -> TextForm {
        // `utf8.count` is O(1); `count` would walk graphemes across a multi-MB copy.
        guard text.utf8.count <= detectionLimit else { return .plain }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .plain }
        // Before the whitespace reject: `rgb(255, 87, 51)` is one value written with spaces.
        if ColorValue.parse(token) != nil { return .color }
        guard !token.contains(where: \.isWhitespace) else { return .plain }
        if let form = schemeForm(of: token) { return form }
        if isAddress(token) { return .email }
        return isBareDomain(token) ? .link : .plain
    }

    /// `mailto:` is an address; any other `scheme://` is a link, so `vscode://` needs no allowlist.
    private static func schemeForm(of token: String) -> TextForm? {
        if token.range(of: "mailto:", options: [.caseInsensitive, .anchored]) != nil {
            return .email
        }
        guard let separator = token.range(of: "://") else { return nil }
        let scheme = token[token.startIndex..<separator.lowerBound]
        guard !scheme.isEmpty,
            scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "+" || $0 == "-" || $0 == ".") })
        else { return nil }
        return .link
    }

    /// `local@domain.tld`: one `@`, a non-empty local part, and a host-shaped domain.
    private static func isAddress(_ token: String) -> Bool {
        let parts = token.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        return topLevelLabel(of: parts[1]) != nil
    }

    /// A heuristic, and deliberately so: its worst case files a row under the wrong type.
    private static func isBareDomain(_ token: String) -> Bool {
        let host = token.prefix { !"/?#:".contains($0) }
        if host.range(of: "www.", options: [.caseInsensitive, .anchored]) != nil { return true }
        // Hosts are canonically lower case, which is what keeps `Safari.app` out of the links.
        guard !host.contains(where: \.isUppercase), let tld = topLevelLabel(of: host) else {
            return false
        }
        return commonTopLevelDomains.contains(String(tld))
    }

    /// Nil unless every label is one, which rejects `@apple.com` before it reads as a domain.
    private static func topLevelLabel(of host: Substring) -> Substring? {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy(isHostLabel), let tld = labels.last,
            tld.count >= 2, tld.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }
        return tld
    }

    private static func isHostLabel(_ label: Substring) -> Bool {
        !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}

struct ClipboardLinkMetadata: Codable, Equatable, Sendable {
    var title: String?
    var summary: String?
    var siteName: String?
    var imageURL: URL?
    var faviconURL: URL?

    static func parse(html: String, baseURL: URL) -> ClipboardLinkMetadata {
        let headSlice: String
        if let closeHead = html.range(of: "</head>", options: .caseInsensitive) {
            headSlice = String(html[..<closeHead.upperBound])
        } else {
            headSlice = String(html.prefix(65_536))
        }

        let metas = extractTags(named: "meta", in: headSlice)
        let links = extractTags(named: "link", in: headSlice)

        func metaContent(forKeys keys: [String]) -> String? {
            for key in keys {
                for attrs in metas {
                    let name = attrs["property"] ?? attrs["name"] ?? attrs["itemprop"]
                    if name?.caseInsensitiveCompare(key) == .orderedSame,
                       let raw = attrs["content"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !raw.isEmpty {
                        return decodeHTMLEntities(raw)
                    }
                }
            }
            return nil
        }

        let title = metaContent(forKeys: ["og:title", "twitter:title"])
            ?? extractTitleTag(in: headSlice).map(decodeHTMLEntities)
        let summary = metaContent(forKeys: ["og:description", "twitter:description", "description"])
        let siteName = metaContent(forKeys: ["og:site_name", "application-name"])
            ?? baseURL.host?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)

        let rawImage = metaContent(forKeys: ["og:image:secure_url", "og:image", "twitter:image", "twitter:image:src"])
        let imageURL = rawImage.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }

        var faviconURL: URL?
        for relPriority in ["apple-touch-icon", "icon", "shortcut icon"] {
            if let match = links.first(where: {
                let rel = ($0["rel"] ?? "").lowercased()
                return rel == relPriority || rel.split(separator: " ").contains(Substring(relPriority))
            }), let href = match["href"]?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty,
               let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                faviconURL = resolved
                break
            }
        }
        if faviconURL == nil, let scheme = baseURL.scheme, let host = baseURL.host {
            faviconURL = URL(string: "\(scheme)://\(host)/favicon.ico")
        }

        return ClipboardLinkMetadata(
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary?.trimmingCharacters(in: .whitespacesAndNewlines),
            siteName: siteName?.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: imageURL,
            faviconURL: faviconURL
        )
    }

    private static let titleRegex = try? NSRegularExpression(
        pattern: #"<title[^>]*>([\s\S]*?)</title>"#,
        options: [.caseInsensitive]
    )
    private static let attrRegex = try? NSRegularExpression(
        pattern: #"([a-zA-Z0-9_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
        options: []
    )

    private static func extractTitleTag(in html: String) -> String? {
        guard let titleRegex else { return nil }
        let ns = html as NSString
        guard let match = titleRegex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1
        else { return nil }
        let raw = ns.substring(with: match.range(at: 1))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    private static func extractTags(named tagName: String, in html: String) -> [[String: String]] {
        guard let tagRegex = try? NSRegularExpression(
            pattern: "<\(tagName)\\b([^>]*)/?>",
            options: [.caseInsensitive]
        ), let attrRegex else { return [] }

        let ns = html as NSString
        let matches = tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        return matches.map { tagMatch in
            let body = ns.substring(with: tagMatch.range(at: 1))
            let nsBody = body as NSString
            let attrMatches = attrRegex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
            var dict: [String: String] = [:]
            for m in attrMatches {
                let key = nsBody.substring(with: m.range(at: 1)).lowercased()
                let valRange: NSRange
                if m.range(at: 2).location != NSNotFound { valRange = m.range(at: 2) }
                else if m.range(at: 3).location != NSNotFound { valRange = m.range(at: 3) }
                else { valRange = m.range(at: 4) }
                if valRange.location != NSNotFound {
                    dict[key] = nsBody.substring(with: valRange)
                }
            }
            return dict
        }
    }

    static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&ndash;", "–"), ("&mdash;", "—")
        ] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        guard let numericRegex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#, options: []) else {
            return result
        }
        let ns = result as NSString
        let matches = numericRegex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return result }
        let mutable = NSMutableString(string: result)
        for match in matches.reversed() {
            let token = ns.substring(with: match.range(at: 1))
            let codePoint: UInt32? = token.lowercased().hasPrefix("x")
                ? UInt32(token.dropFirst(), radix: 16)
                : UInt32(token, radix: 10)
            if let cp = codePoint, let scalar = UnicodeScalar(cp) {
                mutable.replaceCharacters(in: match.range, with: String(scalar))
            }
        }
        return mutable as String
    }
}
