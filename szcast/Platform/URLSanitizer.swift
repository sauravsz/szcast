import Foundation

public enum URLSanitizer: Sendable {
    public struct SanitizeResult: Sendable, Equatable {
        public let originalURL: String
        public let cleanURL: String
        public let removedParameters: [String]
        public let wasUnwrapped: Bool

        public var hasModifications: Bool {
            !removedParameters.isEmpty || wasUnwrapped
        }
    }

    private static let trackingParams: Set<String> = [
        // Google Analytics & Marketing
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_source_platform", "utm_creative_format", "utm_marketing_tactic",
        "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "_ga", "_gl",

        // Facebook / Meta / Instagram
        "fbclid", "fbadid", "igshid", "ig_rid",

        // Twitter / X
        "twclid",

        // Microsoft / Bing / Yahoo
        "msclkid", "yclid",

        // TikTok
        "tt_medium", "tt_content", "_r", "_t",

        // YouTube
        "si", "feature",

        // LinkedIn
        "li_fat_id", "trackingid",

        // Email / Automation (Hubspot, Mailchimp, Marketo, Vero)
        "_hsenc", "_hsmi", "hsctatracking", "mc_cid", "mc_eid", "mkt_tok", "vero_id", "vero_conv",

        // Amazon tracking
        "tag", "ref_", "pf_rd_r", "pf_rd_m", "pf_rd_t", "pf_rd_i", "pf_rd_p", "pf_rd_s",
        "pd_rd_r", "pd_rd_w", "pd_rd_wg",

        // General referral / tracking / session
        "ref", "ref_src", "ref_url", "source", "affiliate", "affiliate_id", "spm"
    ]

    public static func sanitize(_ urlString: String) -> SanitizeResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SanitizeResult(originalURL: urlString, cleanURL: urlString, removedParameters: [], wasUnwrapped: false)
        }

        var target = trimmed
        var wasUnwrapped = false

        if !target.lowercased().hasPrefix("http://") && !target.lowercased().hasPrefix("https://") {
            if let extracted = extractURL(from: target) {
                target = extracted
            } else if target.lowercased().hasPrefix("www.") {
                target = "https://" + target
            }
        }

        // 1. Unwrap common redirect wrappers (Google, Slack, Outlook)
        while let unwrapped = unwrapRedirect(target) {
            target = unwrapped
            wasUnwrapped = true
        }

        // 2. Parse URL components
        guard var components = URLComponents(string: target) else {
            return SanitizeResult(originalURL: urlString, cleanURL: target, removedParameters: [], wasUnwrapped: wasUnwrapped)
        }

        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            return SanitizeResult(originalURL: urlString, cleanURL: target, removedParameters: [], wasUnwrapped: wasUnwrapped)
        }

        var removed: [String] = []
        var retained: [URLQueryItem] = []

        for item in queryItems {
            let lowerKey = item.name.lowercased()
            if trackingParams.contains(lowerKey)
                || lowerKey.hasPrefix("utm_")
                || lowerKey.hasPrefix("ref_")
                || lowerKey.hasPrefix("pd_rd_")
                || lowerKey.hasPrefix("pf_rd_") {
                removed.append(item.name)
            } else {
                retained.append(item)
            }
        }

        components.queryItems = retained.isEmpty ? nil : retained
        let clean = components.string ?? target

        return SanitizeResult(
            originalURL: urlString,
            cleanURL: clean,
            removedParameters: removed,
            wasUnwrapped: wasUnwrapped
        )
    }

    public static func containsURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") {
            return true
        }
        return extractURL(from: trimmed) != nil
    }

    public static func extractURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") && trimmed.hasSuffix(">") {
            let inner = String(trimmed.dropFirst().dropLast())
            if inner.lowercased().hasPrefix("http://") || inner.lowercased().hasPrefix("https://") {
                return inner
            }
        }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            if let firstToken = trimmed.components(separatedBy: .whitespacesAndNewlines).first,
               URL(string: firstToken) != nil {
                return firstToken
            }
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length))
        if let match = matches?.first, let range = Range(match.range, in: trimmed) {
            return String(trimmed[range])
        }
        return nil
    }

    private static func unwrapRedirect(_ urlString: String) -> String? {
        guard let components = URLComponents(string: urlString),
              let host = components.host?.lowercased() else { return nil }

        // Google Redirect: google.com/url?q=<target> or ?url=<target>
        if host.contains("google.") && components.path.hasSuffix("/url") {
            if let target = components.queryItems?.first(where: { $0.name == "q" || $0.name == "url" })?.value,
               !target.isEmpty {
                return target
            }
        }

        // Slack Redirect: slack-redir.net/link?url=<target>
        if host.contains("slack-redir.net") {
            if let target = components.queryItems?.first(where: { $0.name == "url" })?.value,
               !target.isEmpty {
                return target
            }
        }

        // Outlook SafeLinks: safelinks.protection.outlook.com/?url=<target>
        if host.contains("safelinks.protection.outlook.com") {
            if let target = components.queryItems?.first(where: { $0.name == "url" })?.value,
               !target.isEmpty {
                return target
            }
        }

        return nil
    }
}
