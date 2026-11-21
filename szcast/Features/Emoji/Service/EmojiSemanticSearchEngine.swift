import Foundation

@MainActor
enum EmojiSemanticSearchEngine {
    private static let semanticConceptMap: [String: [String]] = [
        // Emotions & Moods
        "tired": ["🥱", "😴", "💤", "🛏️", "😫", "😩", "😮‍💨"],
        "exhausted": ["🥱", "😴", "💤", "😫", "😩", "🥀", "😮‍💨"],
        "sleepy": ["😴", "🥱", "💤", "🛏️", "🌙"],
        "happy": ["😄", "😊", "🥳", "🎉", "✨", "😁", "🤩", "🥰"],
        "excited": ["🤩", "🥳", "🎉", "🔥", "⚡", "🚀", "🙌"],
        "hyped": ["🔥", "⚡", "🚀", "🤩", "🥳", "🙌"],
        "sad": ["😢", "😭", "💔", "🥺", "😞", "😿"],
        "crying": ["😭", "😢", "🥺", "😿", "🌧️"],
        "heartbroken": ["💔", "🥀", "🥺", "😭", "❤️‍🩹"],
        "angry": ["😡", "🤬", "😤", "👿", "💢", "🔥"],
        "furious": ["🤬", "😡", "😤", "👿", "💥"],
        "confused": ["🤔", "🧐", "🤨", "❓", "❔", "😵‍💫"],
        "thinking": ["🤔", "🧐", "💭", "🧠", "💡"],
        "laughing": ["😂", "🤣", "💀", "😆", "😹"],
        "funny": ["😂", "🤣", "💀", "🃏", "🤡"],
        "cool": ["😎", "🕶️", "🤙", "🧊", "💅", "✨"],
        "chill": ["🧘", "🧊", "🤙", "☕", "🍃"],
        "shocked": ["🤯", "😱", "😲", "💥", "⚡", "🙀"],
        "mindblown": ["🤯", "💥", "✨", "🌌"],
        "love": ["❤️", "😍", "🥰", "💖", "💕", "💌", "🫶"],
        "crush": ["🥰", "😍", "💌", "💓", "👀"],

        // Work, Tech & Productivity
        "coding": ["👨‍💻", "👩‍💻", "💻", "⌨️", "🐛", "🖥️", "⚙️"],
        "programming": ["💻", "👨‍💻", "👩‍💻", "⌨️", "🖥️", "⚡"],
        "developer": ["👨‍💻", "👩‍💻", "💻", "⌨️", "🔧", "🛠️"],
        "bug": ["🐛", "🪲", "⚠️", "🚨", "🔧", "🔍"],
        "terminal": ["💻", "⌨️", "🖥️", "⬛"],
        "meeting": ["📅", "👥", "📹", "📞", "🤝", "📊"],
        "call": ["📞", "📱", "🤙", "🎙️", "🎧"],
        "success": ["🏆", "🥇", "🎯", "👑", "✨", "💯"],
        "winning": ["🏆", "🥇", "🥳", "👑", "🎖️"],
        "launch": ["🚀", "🚢", "📦", "🛰️", "🌟", "🎉"],
        "deploy": ["🚀", "📦", "🚢", "☁️", "⚡"],
        "rocket": ["🚀", "🛰️", "🛸", "🌌"],
        "money": ["💰", "💵", "📈", "💎", "💳", "🤑"],
        "crypto": ["🪙", "₿", "📈", "💎", "⛓️"],
        "rich": ["🤑", "💰", "💵", "💎", "👑"],
        "analytics": ["📈", "📊", "📉", "🔍", "📋"],
        "deadline": ["⏰", "⏳", "🚨", "📅", "🔥"],

        // Food & Drinks
        "coffee": ["☕", "☕️", "🧋", "🥐", "🌅"],
        "caffeine": ["☕", "⚡", "🔋", "🍵"],
        "tea": ["🍵", "🫖", "🧋", "🌿"],
        "food": ["🍕", "🍔", "🌮", "🍜", "🤤", "🍽️"],
        "hungry": ["🤤", "🍕", "🍔", "😋", "🍽️"],
        "dinner": ["🍷", "🍝", "🥩", "🕯️", "🍽️"],
        "lunch": ["🥪", "🥗", "🍱", "🍔", "🌯"],
        "breakfast": ["🥞", "🍳", "🥓", "🥐", "☕"],
        "pizza": ["🍕", "🧀", "🇮🇹"],
        "burger": ["🍔", "🍟", "🥤"],
        "drinks": ["🍻", "🥂", "🍸", "🍹", "🍾"],
        "beer": ["🍺", "🍻", "🥨"],
        "wine": ["🍷", "🍾", "🥂", "🍇"],
        "sweet": ["🍰", "🍩", "🍫", "🍪", "🍦", "🍭"],

        // Activities & Life
        "gym": ["🏋️", "💪", "🏃", "🚴", "🥊", "🏅"],
        "workout": ["💪", "🏋️", "🏃", "🤸", "💦"],
        "running": ["🏃", "👟", "⏱️", "💨"],
        "travel": ["✈️", "🏖️", "🌴", "🗺️", "🧳", "🏝️"],
        "vacation": ["🏖️", "🌴", "🏝️", "🍹", "☀️", "✈️"],
        "flight": ["✈️", "🛫", "🛬", "🎫", "☁️"],
        "party": ["🥳", "🎉", "🎊", "🍾", "🍻", "🎈", "🕺"],
        "celebrate": ["🎉", "🥳", "🥂", "🍾", "🎊", "✨"],
        "music": ["🎵", "🎶", "🎧", "🎸", "🎹", "🎤"],
        "gaming": ["🎮", "🕹️", "👾", "🎲"],
        "clean": ["✨", "🧹", "🧼", "🫧", "🧽"],
        "shopping": ["🛍️", "🛒", "💳", "🏷️"],

        // Approvals & Signs
        "yes": ["👍", "✅", "👌", "🤝", "💯", "🙌"],
        "approved": ["✅", "👍", "stamp", "🎯", "💯"],
        "agree": ["🤝", "👍", "✅", "💯"],
        "no": ["👎", "❌", "🙅", "🚫", "⛔"],
        "fire": ["🔥", "⚡", "💥", "💯", "🌶️"],
        "sparkles": ["✨", "🌟", "💫", "⭐"],
        "star": ["⭐", "🌟", "✨", "💫"],
        "idea": ["💡", "🧠", "✨", "🔍"],
        "security": ["🔒", "🛡️", "🔑", "🔐"]
    ]

    static func search(
        _ query: String,
        in index: EmojiIndex,
        frequent: FrequentEmojiStore,
        limit: Int = 30
    ) -> [EmojiEntry] {
        let cleaned = query.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: " ")

        guard !cleaned.isEmpty else { return [] }

        var matchedGlyphs = Set<String>()
        var orderedGlyphs: [String] = []

        let tokens = cleaned.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)

        // 1. Direct concept match
        for token in tokens {
            if let glyphs = semanticConceptMap[token] {
                for g in glyphs {
                    if !matchedGlyphs.contains(g) {
                        matchedGlyphs.insert(g)
                        orderedGlyphs.append(g)
                    }
                }
            }
        }

        // 2. Substring concept match
        for (concept, glyphs) in semanticConceptMap {
            if cleaned.contains(concept) || tokens.contains(where: { concept.hasPrefix($0) || $0.hasPrefix(concept) }) {
                for g in glyphs {
                    if !matchedGlyphs.contains(g) {
                        matchedGlyphs.insert(g)
                        orderedGlyphs.append(g)
                    }
                }
            }
        }

        // Map to valid catalog entries
        var entries: [EmojiEntry] = []
        for g in orderedGlyphs {
            if let entry = index.entry(for: g) {
                entries.append(entry)
            }
            if entries.count >= limit { break }
        }

        return entries
    }
}
