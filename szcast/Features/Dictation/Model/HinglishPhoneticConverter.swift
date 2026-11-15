import Foundation

/// Fast deterministic rule-based Hindi (Devanagari script) to Romanized Latin (Hinglish) phonetic converter.
/// Operates offline with 0ms latency and zero hallucinations.
public enum HinglishPhoneticConverter {

    /// Independent vowels map
    private static let vowels: [Character: String] = [
        "अ": "a",
        "आ": "aa",
        "इ": "i",
        "ई": "ee",
        "उ": "u",
        "ऊ": "oo",
        "ऋ": "ri",
        "ए": "e",
        "ऐ": "ai",
        "ओ": "o",
        "औ": "au"
    ]

    /// Dependent vowel signs (matras)
    private static let matras: [Character: String] = [
        "ा": "a",
        "ि": "i",
        "ी": "i",
        "ु": "u",
        "ू": "u",
        "ृ": "ri",
        "े": "e",
        "ै": "ai",
        "ो": "o",
        "ौ": "au"
    ]

    /// Consonants map
    private static let consonants: [Character: String] = [
        "क": "k",
        "ख": "kh",
        "ग": "g",
        "घ": "gh",
        "ङ": "ng",
        "च": "ch",
        "छ": "chh",
        "ज": "j",
        "झ": "jh",
        "ञ": "ny",
        "ट": "t",
        "ठ": "th",
        "ड": "d",
        "ढ": "dh",
        "ण": "n",
        "त": "t",
        "थ": "th",
        "द": "d",
        "ध": "dh",
        "न": "n",
        "प": "p",
        "फ": "f",
        "ब": "b",
        "भ": "bh",
        "म": "m",
        "य": "y",
        "र": "r",
        "ल": "l",
        "व": "v",
        "श": "sh",
        "ष": "sh",
        "स": "s",
        "ह": "h",
        "ड़": "r",
        "ढ़": "rh",
        "फ़": "f",
        "ज़": "z",
        "क़": "q",
        "ख़": "kh",
        "ग़": "gh",
        "ं": "n",
        "ः": "h",
        "ँ": "n"
    ]

    private static let halant: Character = "्"

    /// Check if text contains any Hindi Devanagari Unicode characters
    public static func containsHindi(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.value >= 0x0900 && scalar.value <= 0x097F
        }
    }

    /// Converts Hindi Devanagari script to Romanized Latin characters (Hinglish)
    public static func convert(_ input: String) -> String {
        guard containsHindi(input) else { return input }

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

                    if next == halant {
                        // Suppresses inherent vowel and links to next consonant
                        index += 1
                        continue
                    } else if let matra = matras[next] {
                        output.append(matra)
                        index += 1
                        continue
                    } else if consonants[next] != nil {
                        // In Devanagari, consonants carry an inherent 'a'
                        // Only append 'a' when between consonants, e.g. "kar" vs "kara"
                    }
                }
                continue
            }

            // 3. Standalone matras
            if let matra = matras[char] {
                output.append(matra)
                index += 1
                continue
            }

            // 4. Non-Devanagari characters (spaces, punctuation, English words, numbers)
            if char != halant {
                output.append(char)
            }
            index += 1
        }

        return cleanupCommonHinglish(output)
    }

    private static func cleanupCommonHinglish(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            ("ky", "kya"),
            ("kse", "kaise"),
            ("hn", "haan"),
            ("nhn", "nahin"),
            ("thk", "theek"),
            ("shkry", "shukriya"),
            ("dhnyvd", "dhanyawad")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .caseInsensitive)
        }
        return result
    }
}
