import CryptoKit
import Foundation

enum CalcDataTransformers {
    static func evaluate(query: String) -> CalcResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()

        // 1. UUID Generation
        if lower == "uuid" || lower == "uuidv4" || lower == "new uuid" || lower == "uuid v4" {
            let id = UUID().uuidString.lowercased()
            return CalcResult(
                expression: trimmed,
                payload: .value(display: id, copyText: id),
                canChain: false
            )
        }
        if lower == "uuid upper" || lower == "uuid uppercase" {
            let id = UUID().uuidString.uppercased()
            return CalcResult(
                expression: trimmed,
                payload: .value(display: id, copyText: id),
                canChain: false
            )
        }

        // 2. Unix / Epoch Now
        if lower == "now as unix" || lower == "unix now" || lower == "epoch now" || lower == "now as epoch" {
            let nowSec = Int64(Date().timeIntervalSince1970)
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let display = "\(nowSec) s (\(nowMs) ms)"
            return CalcResult(
                expression: trimmed,
                payload: .value(display: display, copyText: "\(nowSec)"),
                canChain: false
            )
        }

        // 3. Cryptographic Hashes
        if let text = matchPrefix(lower: lower, original: trimmed, prefixes: ["sha256 ", "sha-256 "]) {
            let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            return CalcResult(
                expression: trimmed,
                payload: .value(display: hash, copyText: hash),
                canChain: false
            )
        }
        if let text = matchPrefix(lower: lower, original: trimmed, prefixes: ["sha1 ", "sha-1 "]) {
            let hash = Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            return CalcResult(
                expression: trimmed,
                payload: .value(display: hash, copyText: hash),
                canChain: false
            )
        }
        if let text = matchPrefix(lower: lower, original: trimmed, prefixes: ["sha512 ", "sha-512 "]) {
            let hash = SHA512.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            return CalcResult(
                expression: trimmed,
                payload: .value(display: hash, copyText: hash),
                canChain: false
            )
        }
        if let text = matchPrefix(lower: lower, original: trimmed, prefixes: ["md5 "]) {
            let hash = Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            return CalcResult(
                expression: trimmed,
                payload: .value(display: hash, copyText: hash),
                canChain: false
            )
        }

        // 4. Base64 Encoding & Decoding
        if let text = matchPrefix(lower: lower, original: trimmed, prefixes: ["base64 decode ", "base64 -d ", "b64 decode "]) {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = Data(base64Encoded: clean) ?? Data(base64Encoded: base64Padded(clean)),
               let decoded = String(data: data, encoding: .utf8) {
                return CalcResult(
                    expression: trimmed,
                    payload: .value(display: decoded, copyText: decoded),
                    canChain: false
                )
            }
        }
        if let text = matchPrefix(lower: lower, original: trimmed, prefixes: ["base64 encode ", "base64 ", "b64 "]) {
            let encoded = Data(text.utf8).base64EncodedString()
            return CalcResult(
                expression: trimmed,
                payload: .value(display: encoded, copyText: encoded),
                canChain: false
            )
        }

        // 5. URL Encoding & Decoding
        if let text = matchPrefix(lower: lower, original: trimmed, prefixes: ["urldecode ", "url decode "]) {
            let decoded = text.removingPercentEncoding ?? text
            return CalcResult(
                expression: trimmed,
                payload: .value(display: decoded, copyText: decoded),
                canChain: false
            )
        }
        if let text = matchPrefix(lower: lower, original: trimmed, prefixes: ["urlencode ", "url encode "]) {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
            return CalcResult(
                expression: trimmed,
                payload: .value(display: encoded, copyText: encoded),
                canChain: false
            )
        }

        // 6. URL Sanitization & Tracking Parameter Stripper
        if let text = matchPrefix(lower: lower, original: trimmed, prefixes: ["cleanurl ", "clean url ", "clean ", "sanitize ", "untrack ", "strip "]) {
            let targetURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if URLSanitizer.containsURL(targetURL) || targetURL.contains("?") {
                let result = URLSanitizer.sanitize(targetURL)
                let count = result.removedParameters.count
                let summary: String
                if result.hasModifications {
                    if result.wasUnwrapped {
                        summary = "Unwrapped & cleaned: \(result.cleanURL)"
                    } else {
                        summary = "Removed \(count) tracking param\(count == 1 ? "" : "s"): \(result.cleanURL)"
                    }
                } else {
                    summary = "Already clean: \(result.cleanURL)"
                }
                return CalcResult(
                    expression: trimmed,
                    payload: .value(display: summary, copyText: result.cleanURL),
                    canChain: false
                )
            }
        }

        // 6. JWT Inspection
        if let text = matchPrefix(lower: lower, original: trimmed, prefixes: ["jwt ", "jwt decode ", "inspect jwt "]) {
            if let jwtResult = inspectJWT(text.trimmingCharacters(in: .whitespacesAndNewlines), query: trimmed) {
                return jwtResult
            }
        }

        // 7. Lorem Ipsum Generator
        if lower.hasPrefix("lorem") {
            if let loremResult = generateLorem(lower: lower, original: trimmed) {
                return loremResult
            }
        }

        return nil
    }

    private static func matchPrefix(lower: String, original: String, prefixes: [String]) -> String? {
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                let index = original.index(original.startIndex, offsetBy: prefix.count)
                let remainder = String(original[index...]).trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty { return remainder }
            }
        }
        return nil
    }

    private static func parseUnixTimestamp(_ string: String) -> TimeInterval? {
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let num = Double(clean) else { return nil }
        // If > 1e11, it's milliseconds
        if num > 100_000_000_000 {
            return num / 1000.0
        }
        return num
    }

    private static func base64Padded(_ str: String) -> String {
        let remainder = str.count % 4
        if remainder == 0 { return str }
        return str + String(repeating: "=", count: 4 - remainder)
    }

    private static func inspectJWT(_ token: String, query: String) -> CalcResult? {
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }

        func decodeSegment(_ segment: String) -> [String: Any]? {
            var b64 = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            b64 = base64Padded(b64)
            guard let data = Data(base64Encoded: b64),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return json
        }

        guard let header = decodeSegment(parts[0]),
              let payload = decodeSegment(parts[1]) else {
            return nil
        }

        let alg = header["alg"] as? String ?? "none"
        let sub = payload["sub"] as? String ?? payload["userId"] as? String ?? ""

        var expText = ""
        if let expNum = payload["exp"] as? Double {
            let expDate = Date(timeIntervalSince1970: expNum)
            let isExpired = expDate < Date()
            let rel = RelativeDateTimeFormatter().localizedString(for: expDate, relativeTo: Date())
            expText = isExpired ? "Expired \(rel)" : "Expires \(rel)"
        }

        var partsSummary: [String] = ["alg: \(alg)"]
        if !sub.isEmpty { partsSummary.append("sub: \(sub)") }
        if !expText.isEmpty { partsSummary.append(expText) }

        let display = partsSummary.joined(separator: " • ")

        // Format clean JSON for clipboard copy
        var copyPayload: [String: Any] = ["header": header, "payload": payload]
        if let prettyData = try? JSONSerialization.data(withJSONObject: copyPayload, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return CalcResult(expression: query, payload: .value(display: display, copyText: prettyString), canChain: false)
        }

        return CalcResult(expression: query, payload: .value(display: display, copyText: display), canChain: false)
    }

    private static func generateLorem(lower: String, original: String) -> CalcResult? {
        let words = [
            "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
            "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore",
            "magna", "aliqua", "ut", "enim", "ad", "minim", "veniam", "quis", "nostrud",
            "exercitation", "ullamco", "laboris", "nisi", "ut", "aliquip", "ex", "ea",
            "commodo", "consequat", "duis", "aute", "irure", "dolor", "in", "reprehenderit",
            "in", "voluptate", "velit", "esse", "cillum", "dolore", "eu", "fugiat", "nulla",
            "pariatur", "excepteur", "sint", "occaecat", "cupidatat", "non", "proident",
            "sunt", "in", "culpa", "qui", "officia", "deserunt", "mollit", "anim", "id", "est", "laborum"
        ]

        var wordCount = 30
        var paragraphCount = 1

        let scanner = Scanner(string: lower)
        _ = scanner.scanString("lorem")
        _ = scanner.scanCharacters(from: .whitespaces)

        if scanner.scanString("ipsum") != nil {
            _ = scanner.scanCharacters(from: .whitespaces)
        }

        if let count = scanner.scanInt() {
            if scanner.scanString("p") != nil || scanner.scanString("paragraphs") != nil {
                paragraphCount = max(1, min(10, count))
                wordCount = paragraphCount * 45
            } else if scanner.scanString("w") != nil || scanner.scanString("words") != nil {
                wordCount = max(5, min(500, count))
                paragraphCount = 1
            } else {
                wordCount = max(5, min(500, count))
            }
        }

        var resultWords: [String] = []
        for i in 0..<wordCount {
            resultWords.append(words[i % words.count])
        }

        if paragraphCount > 1 {
            var paragraphs: [String] = []
            let wordsPerParagraph = wordCount / paragraphCount
            for p in 0..<paragraphCount {
                let start = p * wordsPerParagraph
                let end = min(start + wordsPerParagraph, resultWords.count)
                var pWords = Array(resultWords[start..<end])
                if let first = pWords.first {
                    pWords[0] = first.capitalized
                }
                paragraphs.append(pWords.joined(separator: " ") + ".")
            }
            let fullText = paragraphs.joined(separator: "\n\n")
            let preview = paragraphs[0]
            return CalcResult(expression: original, payload: .value(display: "\(paragraphCount) paragraphs: \(preview)", copyText: fullText), canChain: false)
        } else {
            resultWords[0] = resultWords[0].capitalized
            let fullText = resultWords.joined(separator: " ") + "."
            let preview = fullText.count > 50 ? String(fullText.prefix(47)) + "..." : fullText
            return CalcResult(expression: original, payload: .value(display: preview, copyText: fullText), canChain: false)
        }
    }
}
