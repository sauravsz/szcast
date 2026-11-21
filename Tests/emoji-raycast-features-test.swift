import Foundation

@main
@MainActor
struct EmojiRaycastFeaturesTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async {
        print("Testing Raycast Emoji Features...")

        // 1. Custom Keywords Store
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeURL = tempDir.appendingPathComponent("custom-emoji.json")
        let customStore = CustomEmojiKeywordStore(fileURL: storeURL)

        customStore.setKeywords(["hyper", "speedy", "supersonic"], for: "🚀")
        expect(customStore.keywords(for: "🚀") == ["hyper", "speedy", "supersonic"], "Custom keywords saved and retrieved")

        customStore.addKeyword("blastoff", for: "🚀")
        expect(customStore.keywords(for: "🚀").contains("blastoff"), "Added single keyword to existing")

        // 2. Inline Completion Token Detection
        let inline = InlineEmojiCompletionService()
        let t1 = inline.detectTrigger(in: ":smile", cursorLocation: 6)
        expect(t1?.token == "smile" && t1?.range.location == 0 && t1?.range.length == 6, ":smile detected at start")

        let t2 = inline.detectTrigger(in: "Hello :wave world", cursorLocation: 11)
        expect(t2?.token == "wave" && t2?.range.location == 6 && t2?.range.length == 5, ":wave detected after space")

        let t3 = inline.detectTrigger(in: "http://example.com:8080", cursorLocation: 23)
        expect(t3 == nil, "Colon in URL not detected as emoji trigger")

        let t4 = inline.detectTrigger(in: ":a", cursorLocation: 2)
        expect(t4?.token == "a", "Single char query detected")

        // 3. Skin Tone Resolution
        let waveEntry = EmojiEntry(
            glyph: "👋",
            name: "waving hand",
            category: .smileysAndPeople,
            supportsSkinTone: true,
            keywords: "hand,wave"
        )
        expect(waveEntry.display(tone: .none) == "👋", "Default skin tone keeps base glyph")
        expect(waveEntry.display(tone: .light) == "👋🏻", "Light skin tone applied")
        expect(waveEntry.display(tone: .dark) == "👋🏿", "Dark skin tone applied")

        // 4. Primary Actions
        let pasteAction = EmojiPrimaryAction.paste
        let copyAction = EmojiPrimaryAction.copy
        expect(pasteAction.rawValue == "paste", "Primary action paste enum matches")
        expect(copyAction.rawValue == "copy", "Primary action copy enum matches")

        // 5. Semantic Search Concept Matching
        let testCatalog = EmojiCatalog.parse(EmojiData.raw)
        let testIndex = EmojiIndex()
        await testIndex.load()
        let frequentStore = FrequentEmojiStore(fileURL: tempDir.appendingPathComponent("frequent.json"))

        let coffeeResults = testIndex.searchAIResults("coffee", frequent: frequentStore)
        expect(!coffeeResults.isEmpty, "Semantic search finds coffee emojis")
        expect(coffeeResults.contains(where: { $0.glyph.contains("☕") }), "Found coffee cup in semantic search")

        let rocketResults = testIndex.searchAIResults("launch", frequent: frequentStore)
        expect(rocketResults.contains(where: { $0.glyph == "🚀" }), "Found rocket in launch semantic search")

        // 6. Unicode formatting
        let scalars = "👋🏻".unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
        expect(scalars.contains("U+1F44B") && scalars.contains("U+1F3FB"), "Unicode scalar conversion correct")

        try? FileManager.default.removeItem(at: tempDir)

        if failures > 0 {
            print("FAILED: \(failures) failures in emoji raycast features test")
            exit(1)
        } else {
            print("PASSED: All \(passes) assertions passed")
        }
    }
}
