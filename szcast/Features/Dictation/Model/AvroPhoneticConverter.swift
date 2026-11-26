import Foundation

/// Fast deterministic rule-based Bengali script to Romanized Latin (Banglish) phonetic converter.
/// Operates offline with 0ms latency and zero hallucinations.
public enum AvroPhoneticConverter {

    private static let vowels: [Unicode.Scalar: String] = [
        "অ": "o", "আ": "a", "ই": "i", "ঈ": "i", "উ": "u", "ঊ": "u",
        "ঋ": "ri", "এ": "e", "ঐ": "oi", "ও": "o", "ঔ": "ou"
    ]

    private static let vowelSigns: [Unicode.Scalar: String] = [
        "া": "a", "ি": "i", "ী": "i", "ু": "u", "ূ": "u",
        "ৃ": "ri", "ে": "e", "ৈ": "oi", "ো": "o", "ৌ": "ou"
    ]

    private static let consonants: [Unicode.Scalar: String] = [
        "ক": "k", "খ": "kh", "গ": "g", "ঘ": "gh", "ঙ": "ng",
        "চ": "ch", "ছ": "chh", "জ": "j", "ঝ": "jh", "ঞ": "ng",
        "ট": "t", "ঠ": "th", "ড": "d", "ঢ": "dh", "ণ": "n",
        "ত": "t", "থ": "th", "দ": "d", "ধ": "dh", "ন": "n",
        "প": "p", "ফ": "f", "ব": "b", "ভ": "bh", "ম": "m",
        "য": "j", "র": "r", "ল": "l", "শ": "sh", "ষ": "sh", "স": "s", "হ": "h",
        "ড়": "r", "ঢ়": "rh", "য়": "y", "ৎ": "t"
    ]

    private static let nuktaConsonants: [Unicode.Scalar: String] = [
        "ড": "r", "ঢ": "rh", "য": "y"
    ]

    private static let nasalModifiers: [Unicode.Scalar: String] = [
        "ং": "ng", "ঃ": "h", "ঁ": "n"
    ]

    private static let punctuationModifiers: [Unicode.Scalar: String] = [
        "।": ".", "॥": "."
    ]

    private static let digits: [Unicode.Scalar: String] = [
        "০": "0", "১": "1", "২": "2", "৩": "3", "৪": "4",
        "৫": "5", "৬": "6", "৭": "7", "৮": "8", "৯": "9"
    ]

    private static let hasanta: Unicode.Scalar = "্"
    private static let nukta: Unicode.Scalar = "়"

    /// Check if text contains any Bengali Unicode characters.
    public static func containsBengali(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.value >= 0x0980 && scalar.value <= 0x09FF
        }
    }

    /// Converts Bengali script to Romanized Latin characters (Banglish).
    public static func convert(_ input: String) -> String {
        guard containsBengali(input) else { return input }

        var output = ""
        let scalars = Array(input.unicodeScalars)
        let count = scalars.count
        var index = 0
        var prevWasBareConsonant = false
        var afterHasanta = false

        while index < count {
            let scalar = scalars[index]

            if let v = vowels[scalar] {
                output.append(v)
                prevWasBareConsonant = false
                afterHasanta = false
                index += 1
                continue
            }

            if let d = digits[scalar] {
                output.append(d)
                prevWasBareConsonant = false
                afterHasanta = false
                index += 1
                continue
            }

            if let m = nasalModifiers[scalar] ?? punctuationModifiers[scalar] {
                output.append(m)
                prevWasBareConsonant = false
                afterHasanta = false
                index += 1
                continue
            }

            if var c = consonants[scalar] {
                if afterHasanta, scalar == "য" {
                    c = "y"
                }
                index += 1
                if index < count, scalars[index] == nukta {
                    c = nuktaConsonants[scalar] ?? c
                    index += 1
                }
                afterHasanta = false
                output.append(c)

                if index < count, scalars[index] == hasanta {
                    index += 1
                    prevWasBareConsonant = false
                    afterHasanta = true
                } else if index < count, let sign = vowelSigns[scalars[index]] {
                    output.append(sign)
                    index += 1
                    prevWasBareConsonant = false
                } else if index < count, consonants[scalars[index]] != nil || nasalModifiers[scalars[index]] != nil {
                    // Delete medial 'o' in VC.CV words (e.g. "korte"), keep it otherwise ("kemon").
                    let deletesMedialVowel = prevWasBareConsonant
                        && index + 1 < count
                        && consonants[scalars[index]] != nil
                        && vowelSigns[scalars[index + 1]] != nil
                    if !deletesMedialVowel {
                        output.append("o")
                        prevWasBareConsonant = consonants[scalars[index]] != nil
                    } else {
                        prevWasBareConsonant = false
                    }
                } else {
                    prevWasBareConsonant = false
                }
                continue
            }

            if let sign = vowelSigns[scalar] {
                output.append(sign)
            } else if scalar != hasanta && scalar != nukta {
                output.unicodeScalars.append(scalar)
            }
            prevWasBareConsonant = false
            afterHasanta = false
            index += 1
        }

        return cleanupCommonBanglish(output)
    }

    private static let cleanupRules: [(regex: NSRegularExpression, replacement: String)] = {
        let pairs: [(String, String)] = [
            ("kmn", "kemon"),
            ("shndr", "shundor"),
            ("dhnbd", "dhonnobad")
        ]
        return pairs.compactMap { token, repl in
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: token) + #"\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, repl)
        }
    }()

    private static func cleanupCommonBanglish(_ text: String) -> String {
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
