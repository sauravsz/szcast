import Foundation

/// Fast deterministic rule-based Hindi (Devanagari script) to Romanized Latin (Hinglish) phonetic converter.
/// Operates offline with 0ms latency and zero hallucinations.
public enum HinglishPhoneticConverter {

    private static let vowels: [Unicode.Scalar: String] = [
        "अ": "a", "आ": "aa", "इ": "i", "ई": "ee", "उ": "u", "ऊ": "oo",
        "ऋ": "ri", "ए": "e", "ऐ": "ai", "ओ": "o", "औ": "au", "ऑ": "o"
    ]

    private static let matras: [Unicode.Scalar: String] = [
        "ा": "a", "ि": "i", "ी": "i", "ु": "u", "ू": "u",
        "ृ": "ri", "े": "e", "ै": "ai", "ो": "o", "ौ": "au",
        "ॅ": "e", "ॉ": "o", "ॆ": "e", "ॊ": "o"
    ]

    private static let consonants: [Unicode.Scalar: String] = [
        "क": "k", "ख": "kh", "ग": "g", "घ": "gh", "ङ": "ng",
        "च": "ch", "छ": "chh", "ज": "j", "झ": "jh", "ञ": "ny",
        "ट": "t", "ठ": "th", "ड": "d", "ढ": "dh", "ण": "n",
        "त": "t", "थ": "th", "द": "d", "ध": "dh", "न": "n",
        "प": "p", "फ": "ph", "ब": "b", "भ": "bh", "म": "m",
        "य": "y", "र": "r", "ल": "l", "ळ": "l", "व": "v",
        "श": "sh", "ष": "sh", "स": "s", "ह": "h",
        "ड़": "r", "ढ़": "rh", "फ़": "f", "ज़": "z", "क़": "q", "ख़": "kh", "ग़": "gh"
    ]

    private static let nuktaConsonants: [Unicode.Scalar: String] = [
        "ड": "r", "ढ": "rh", "फ": "f", "ज": "z", "क": "q", "ख": "kh", "ग": "gh"
    ]

    private static let nasalModifiers: [Unicode.Scalar: String] = [
        "ं": "n", "ः": "h", "ँ": "n"
    ]

    private static let punctuationModifiers: [Unicode.Scalar: String] = [
        "।": ".", "॥": "."
    ]

    private static let digits: [Unicode.Scalar: String] = [
        "०": "0", "१": "1", "२": "2", "३": "3", "४": "4",
        "५": "5", "६": "6", "७": "7", "८": "8", "९": "9"
    ]

    private static let halant: Unicode.Scalar = "्"
    private static let nukta: Unicode.Scalar = "़"

    /// Check if text contains any Hindi Devanagari Unicode characters.
    public static func containsHindi(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.value >= 0x0900 && scalar.value <= 0x097F
        }
    }

    /// Transliterates Devanagari Hindi to Latin letters when Hinglish conversion is requested
    /// or when an Indic CoreML model (`SraVaani`) emits native Devanagari script.
    static func normalizeIfNeeded(
        _ text: String,
        hindiMode: DictationHindiMode,
        isCloud: Bool,
        localModel: DictationModel
    ) -> String {
        if hindiMode == .phoneticEngine {
            return convert(text)
        }
        if (!isCloud && (localModel == .sravaani || localModel == .whisperApex || localModel == .indicFlex))
            || (hindiMode != .off && containsHindi(text)) {
            return convert(text)
        }
        return text
    }

    /// Converts Hindi Devanagari script to Romanized Latin characters (Hinglish).
    public static func convert(_ input: String) -> String {
        guard containsHindi(input) else { return input }

        var output = ""
        let scalars = Array(input.unicodeScalars)
        let count = scalars.count
        var index = 0
        var prevWasBareConsonant = false

        while index < count {
            let scalar = scalars[index]

            if let v = vowels[scalar] {
                output.append(v)
                prevWasBareConsonant = false
                index += 1
                continue
            }

            if let d = digits[scalar] {
                output.append(d)
                prevWasBareConsonant = false
                index += 1
                continue
            }

            if let m = nasalModifiers[scalar] ?? punctuationModifiers[scalar] {
                output.append(m)
                prevWasBareConsonant = false
                index += 1
                continue
            }

            if var c = consonants[scalar] {
                let isKsha = scalar == "क" && index + 2 < count
                    && scalars[index + 1] == halant && scalars[index + 2] == "ष"
                let isGya = scalar == "ज" && index + 2 < count
                    && scalars[index + 1] == halant && scalars[index + 2] == "ञ"
                let isTra = scalar == "त" && index + 2 < count
                    && scalars[index + 1] == halant && scalars[index + 2] == "र"
                let isShra = scalar == "श" && index + 2 < count
                    && scalars[index + 1] == halant && scalars[index + 2] == "र"
                if isKsha || isGya || isTra || isShra {
                    c = isKsha ? "ksh" : (isGya ? "gy" : (isTra ? "tr" : "shr"))
                    index += 3
                } else {
                    index += 1
                    if index < count, scalars[index] == nukta {
                        c = nuktaConsonants[scalar] ?? c
                        index += 1
                    }
                }

                output.append(c)
                if index < count, scalars[index] == halant {
                    index += 1
                    prevWasBareConsonant = false
                } else if index < count, let matra = matras[scalars[index]] {
                    output.append(matra)
                    index += 1
                    prevWasBareConsonant = false
                } else if index < count, consonants[scalars[index]] != nil || nasalModifiers[scalars[index]] != nil {
                    // Delete medial schwa on VC.CV words (e.g. "karna"), keep it otherwise ("kamal", "namaste").
                    let deletesMedialSchwa = prevWasBareConsonant
                        && index + 1 < count
                        && consonants[scalars[index]] != nil
                        && matras[scalars[index + 1]] != nil
                    if !deletesMedialSchwa {
                        output.append("a")
                        prevWasBareConsonant = consonants[scalars[index]] != nil
                    } else {
                        prevWasBareConsonant = false
                    }
                } else {
                    prevWasBareConsonant = false
                }
                continue
            }

            if let matra = matras[scalar] {
                output.append(matra)
            } else if scalar != halant && scalar != nukta {
                output.unicodeScalars.append(scalar)
            }
            prevWasBareConsonant = false
            index += 1
        }

        return cleanupCommonHinglish(output)
    }

    private static let cleanupRules: [(regex: NSRegularExpression, replacement: String)] = {
        let pairs: [(String, String)] = [
            ("ky", "kya"),
            ("kse", "kaise"),
            ("hn", "haan"),
            ("nhn", "nahin"),
            ("thk", "theek"),
            ("shkry", "shukriya"),
            ("dhnyvd", "dhanyawad")
        ]
        return pairs.compactMap { token, repl in
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: token) + #"\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, repl)
        }
    }()

    private static func cleanupCommonHinglish(_ text: String) -> String {
        var result = text
        for rule in cleanupRules {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result, options: [], range: range, withTemplate: rule.replacement
            )
        }
        return result
    }
}
