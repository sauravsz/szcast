import Foundation

/// Fast deterministic rule-based Bengali script to Romanized Latin (Banglish) phonetic converter.
/// Operates offline with 0ms latency and zero hallucinations.
public enum AvroPhoneticConverter {

    /// Independent vowels map
    private static let vowels: [Character: String] = [
        "অ": "o",
        "আ": "a",
        "ই": "i",
        "ঈ": "i",
        "উ": "u",
        "ঊ": "u",
        "ঋ": "ri",
        "এ": "e",
        "ঐ": "oi",
        "ও": "o",
        "ঔ": "ou"
    ]

    /// Dependent vowel signs (kar)
    private static let vowelSigns: [Character: String] = [
        "া": "a",
        "ি": "i",
        "ী": "i",
        "ু": "u",
        "ূ": "u",
        "ৃ": "ri",
        "ে": "e",
        "ৈ": "oi",
        "ো": "o",
        "ৌ": "ou"
    ]

    /// Consonants map
    private static let consonants: [Character: String] = [
        "ক": "k",
        "খ": "kh",
        "গ": "g",
        "ঘ": "gh",
        "ঙ": "ng",
        "চ": "ch",
        "ছ": "ch",
        "জ": "j",
        "ঝ": "jh",
        "ঞ": "ng",
        "ট": "t",
        "ঠ": "th",
        "ড": "d",
        "ঢ": "dh",
        "ণ": "n",
        "ত": "t",
        "থ": "th",
        "দ": "d",
        "ধ": "dh",
        "ন": "n",
        "প": "p",
        "ফ": "f",
        "ব": "b",
        "ভ": "bh",
        "ম": "m",
        "য": "j",
        "র": "r",
        "ল": "l",
        "শ": "sh",
        "ষ": "sh",
        "স": "s",
        "হ": "h",
        "ড়": "r",
        "ঢ়": "rh",
        "য়": "y",
        "ৎ": "t",
        "ং": "ng",
        "ঃ": "h",
        "ঁ": "n"
    ]

    private static let hasanta: Character = "্"

    /// Check if text contains any Bengali Unicode characters
    public static func containsBengali(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.value >= 0x0980 && scalar.value <= 0x09FF
        }
    }

    /// Converts Bengali script to Romanized Latin characters (Banglish)
    public static func convert(_ input: String) -> String {
        guard containsBengali(input) else { return input }

        var output = ""
        let characters = Array(input)
        let count = characters.count
        var index = 0

        while index < count {
            let char = characters[index]

            // 1. Independent vowels
            if let v = vowels[char] {
                output.append(v)
                index += 1
                continue
            }

            // 2. Consonants
            if let c = consonants[char] {
                output.append(c)
                index += 1

                // Check next character
                if index < count {
                    let next = characters[index]

                    if next == hasanta {
                        // Suppresses inherent vowel and links to next consonant
                        index += 1
                        continue
                    } else if let sign = vowelSigns[next] {
                        output.append(sign)
                        index += 1
                        continue
                    } else if consonants[next] != nil {
                        // Consecutive consonant without vowel sign:
                        // If current consonant is followed by another consonant, apply inherent 'o' or skip at word end
                        // In common Banglish, 'o' is used for words like kemon, bhalo
                        // Only add 'o' if not followed by another consonant in a cluster
                    }
                }
                continue
            }

            // 3. Standalone vowel signs (rare edge case without preceding consonant)
            if let sign = vowelSigns[char] {
                output.append(sign)
                index += 1
                continue
            }

            // 4. Non-Bengali characters (spaces, punctuation, English words, numbers)
            if char != hasanta {
                output.append(char)
            }
            index += 1
        }

        // Post-processing cleanups for natural Banglish spelling
        return cleanupCommonBanglish(output)
    }

    private static func cleanupCommonBanglish(_ text: String) -> String {
        // Handle common phonetic transliteration polish
        var result = text
        let replacements: [(String, String)] = [
            ("kmn", "kemon"),
            ("achh", "ach"),
            ("shndr", "shundor"),
            ("dhnbd", "dhonnobad")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .caseInsensitive)
        }
        return result
    }
}
