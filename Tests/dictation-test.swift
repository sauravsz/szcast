import Foundation

@main
struct DictationTest {
    @MainActor
    static func main() {
        let locale = Locale(identifier: "en_US")
        func check(_ actual: String, _ expected: String) {
            guard actual == expected else {
                print("Expected \(expected.debugDescription), got \(actual.debugDescription)")
                exit(1)
            }
        }

        typealias Context = DictationTextFormatter.Context
        check(DictationTextFormatter.format("  Hello. \n", context: nil), "Hello. ")
        check(DictationTextFormatter.format("hello", context: Context(before: "", after: "")), "Hello")
        check(DictationTextFormatter.format("World", context: Context(before: "Hello", after: "")), "World")
        check(DictationTextFormatter.format("world", context: Context(before: "Hello.", after: "")), "World")
        check(DictationTextFormatter.format("hello", context: Context(before: "Wait. ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("hello", context: Context(before: "Wait\n  ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("World", context: Context(before: "Hello ", after: "again")),
            "World ")
        check(DictationTextFormatter.format("hello", context: Context(before: "(", after: ")")), "Hello")
        check(
            DictationTextFormatter.format("application", context: Context(before: "l’", after: "")),
            "Application")
        check(
            DictationTextFormatter.format(
                "szcast", context: Context(before: "Use", after: "again"),
                adaptCapitalization: false), "Szcast ")
        check(
            DictationTextFormatter.format(
                "world", context: Context(before: "Hello.", after: ""),
                adaptCapitalization: false), "World")
        check(
            DictationTextFormatter.format(
                "hello", context: Context(before: "", after: ""),
                adaptCapitalization: false), "Hello")
        check(
            DictationTextFormatter.format(
                "World.", context: Context(before: "Hello ", after: ")"),
                adaptCapitalization: false), "World.")
        // Sentence full stop automatically appends trailing space at boundary or no context
        check(
            DictationTextFormatter.format("This is a sentence.", context: Context(before: "", after: "")),
            "This is a sentence. ")
        check(
            DictationTextFormatter.format("This is a question?", context: nil),
            "This is a question? ")
        check(
            DictationTextFormatter.format("Great job!", context: nil),
            "Great job! ")
        check(
            DictationTextFormatter.format("He said, \"Welcome.\"", context: nil),
            "He said, \"Welcome.\" ")
        // Avoid double spacing when following character in document already has whitespace
        check(
            DictationTextFormatter.format("Hello.", context: Context(before: "", after: " next")),
            "Hello.")
        let document = "prefix. Text to replace suffix"
        check(
            DictationTextFormatter.format(
                "world",
                context: Context(
                    before: document.prefix(7), after: document.suffix(6))), "World ")
        check(DictationTextFormatter.stripEcho(" world peace", after: "Hello world"), " peace")
        check(DictationTextFormatter.stripEcho("theatre tickets", after: "said the"), "theatre tickets")
        check(DictationTextFormatter.stripEcho(" world", after: "Hello world"), "")
        check(DictationTextFormatter.stripEcho("good morning", after: "Hello world"), "good morning")
        check(DictationTextFormatter.stripEcho(" hello", after: ""), " hello")
        check(
            DictationTextFormatter.stripEcho("Für, Jonathan", after: "kein kuchen für"),
            " Jonathan")
        check(
            DictationTextFormatter.stripEcho("ein Kuchen für Jonathan", after: "aber kein Kuchen für"),
            " Jonathan")
        check(
            DictationTextFormatter.stripEcho("äh also weiter gehts", after: "und dann"),
            "äh also weiter gehts")

        // Spoken Emoji conversion
        check(DictationTextFormatter.convertSpokenEmoji("good job thumbs up emoji"), "good job 👍")
        check(DictationTextFormatter.convertSpokenEmoji("this is fire emoji"), "this is 🔥")

        // Spoken Punctuation conversion
        check(DictationTextFormatter.convertSpokenPunctuation("hello comma world period"), "hello, world.")
        check(DictationTextFormatter.convertSpokenPunctuation("are you ready question mark"), "are you ready?")
        check(DictationTextFormatter.convertSpokenPunctuation("First sentence.Second sentence."), "First sentence. Second sentence.")
        check(DictationTextFormatter.convertSpokenPunctuation("Are you ready?Yes I am!"), "Are you ready? Yes I am!")

        // Filler words removal
        check(DictationTextFormatter.removeFillerWords("Um, this is uh a test"), "this is a test")

        // Repetition & Stutter Collapse
        check(DictationTextFormatter.collapseRepetitions("can you tell the the launch is slipping"), "can you tell the launch is slipping")
        check(DictationTextFormatter.collapseRepetitions("timeline by by end of week"), "timeline by end of week")
        check(DictationTextFormatter.collapseRepetitions("we we we are ready"), "we are ready")

        // S1 Control Line
        let s1 = DictationS1Settings(enabled: true, tone: .formal, structure: .lists, context: .email)
        check(s1.controlLine, "[Styling: formal] [Structure: lists] [Context: email]")

        // S1 Output Cleaning & Normalization
        check(DictationS1Polisher.cleanOutput("<think>reasoning</think>hello world") ?? "", "Hello world")
        check(DictationS1Polisher.cleanOutput("<think>unclosed thought\nmore text") ?? "", "")
        check(DictationS1Polisher.cleanOutput("<think>thought</think>  \"this is a quote\"") ?? "", "This is a quote")
        check(DictationS1Polisher.cleanOutput("```\nsome code block\n```") ?? "", "Some code block")
        check(DictationS1Polisher.cleanOutput("   leading spaces and first lower") ?? "", "Leading spaces and first lower")
        check(DictationS1Polisher.cleanOutput("“curly quotes”") ?? "", "Curly quotes")

        // Vocabulary Packs
        check(VocabularyPackType.tech.displayName, "Tech")
        guard VocabularyPackType.tech.fixesCount == 76 else {
            fatalError("Tech vocabulary pack should have 76 fixes")
        }
        guard VocabularyPackType.medical.fixesCount == 87 else {
            fatalError("Medical vocabulary pack should have 87 fixes")
        }

        let tempWordsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-words.json")
        let tempSnippetsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-snippets.json")
        defer {
            try? FileManager.default.removeItem(at: tempWordsURL)
            try? FileManager.default.removeItem(at: tempSnippetsURL)
        }

        let store = DictationDictionaryStore(fileURL: tempWordsURL, snippetsFileURL: tempSnippetsURL)
        check(String(store.loadedTermsCount(for: .tech)), "76")
        check(String(store.loadedTermsCount(for: .medical)), "87")
        check(String(store.loadedTermsCount(for: .legal)), "32")
        check(String(store.loadedTermsCount(for: .brands)), "106")
        check(String(store.loadedTermsCount(for: .names)), "90")

        // Enable all packs for comprehensive testing
        store.enabledPacks = Set(VocabularyPackType.allCases)

        // Test alias replacement
        // Tech (real aliases from tech.json: esync -> async, angularge -> AngularJS, autosculum -> autoscaling)
        check(store.applyDictionaryAndPacks("I am writing esync code for angularge with autosculum"),
              "I am writing async code for AngularJS with autoscaling")

        // Brands
        check(store.applyDictionaryAndPacks("I ate at mcdennalls and ordered addides shoes"),
              "I ate at McDonald's and ordered adidas shoes")
        check(store.applyDictionaryAndPacks("I ate at mcdonalds"),
              "I ate at McDonald's")
        check(store.applyDictionaryAndPacks("I ate at mcdonald’s"),
              "I ate at McDonald's")

        // Medical
        check(store.applyDictionaryAndPacks("take acidaminophan for your ankle"),
              "take acetaminophen for your ankle")

        // Names
        check(store.applyDictionaryAndPacks("meeting with aguary and acosto tomorrow"),
              "meeting with Aguirre and Acosta tomorrow")

        // Legal
        check(store.applyDictionaryAndPacks("file the epilati brief in archord"),
              "file the appellate brief in accord")

        // Disabled pack behavior
        store.enabledPacks = [.tech]
        check(store.applyDictionaryAndPacks("esync and addides"),
              "async and addides")

        // Re-enable brands
        store.enabledPacks = [.tech, .brands]
        check(store.applyDictionaryAndPacks("esync and addides"),
              "async and adidas")

        // Custom words precedence over packs
        store.addWord(canonical: "CustomAsync", aliases: ["esync"])
        check(store.applyDictionaryAndPacks("running esync"),
              "running CustomAsync")

        // Snippets
        store.addSnippet(keyword: "brb", expansion: "be right back")
        check(store.applySnippets("I will brb"), "I will be right back")

        // Dictation Hotkey Presets
        check(DictationHotkeyPreset.fn.binding == .globe ? "true" : "false", "true")
        check(DictationHotkeyPreset.optionSpace.binding == DictationHotkeyPreset.optionSpaceBinding ? "true" : "false", "true")
        check(DictationHotkeyPreset.controlSpace.binding == DictationHotkeyPreset.controlSpaceBinding ? "true" : "false", "true")
        check(DictationHotkeyPreset.custom.binding == nil ? "true" : "false", "true")

        check(DictationHotkeyPreset.preset(for: .globe).rawValue, "fn")
        check(DictationHotkeyPreset.preset(for: DictationHotkeyPreset.optionSpaceBinding).rawValue, "option_space")
        check(DictationHotkeyPreset.preset(for: DictationHotkeyPreset.controlSpaceBinding).rawValue, "control_space")
        check(DictationHotkeyPreset.preset(for: nil).rawValue, "custom")

        let customCombo = HotKeyBinding.combo(KeyShortcut(carbonKeyCode: 2, carbonModifiers: 256))
        check(DictationHotkeyPreset.preset(for: customCombo).rawValue, "custom")

        check(DictationModel.redux.folderName, "parakeet-redux")
        check(DictationModel.ultra.folderName, "parakeet-ultra")
        check(DictationModel.redux.title, "Parakeet · Redux")
        check(DictationModel.ultra.title, "Parakeet · Ultra")
        check(DictationIdleRelease.allCases.map(\.rawValue).description, "[0, 1, 2, 5, 10, 15, 20, 30, 60]")
        check(DictationIdleRelease.never.title(locale: locale), "Never")
        check(DictationIdleRelease.oneHour.title(locale: locale), "1 hour")
        check(DictationIdleRelease.oneHour.title(locale: Locale(identifier: "fr_FR")), "1\u{00a0}heure")
        check(DictationPasteMode.allAtOnce.rawValue, "allAtOnce")
        check(DictationPasteMode.allCases.count.description, "1")
        check(DictationLanguage.english.displayName(locale: locale), "English")
        check(DictationLanguage.english.displayName(locale: Locale(identifier: "de_DE")), "Englisch")
        check(DictationLanguage.english.rawValue, "English")
        check(DictationModel.qwenSmall.folderName, "qwen-0.6b")
        check(DictationModel.qwenLarge.folderName, "qwen-1.7b")
        for family in DictationModel.Family.allCases {
            guard DictationModel.allCases.contains(where: { $0.family == family }) else {
                fatalError("Every engine should expose at least one model")
            }
        }
        for model in DictationModel.allCases {
            guard !model.components.isEmpty, model.revision.count == 40,
                model.requiredFiles.isSuperset(of: model.components)
            else {
                fatalError("Model installation metadata is incomplete")
            }
            if let configuration = model.parakeetConfiguration {
                guard (model.family == .parakeet || model.family == .sravaani), configuration.blankToken == 8192,
                    configuration.encoderUsesGPU == (model == .redux || model == .sravaani),
                    model.components.contains(configuration.joint + ".mlmodelc")
                else {
                    fatalError("Parakeet download and inference disagree")
                }
            } else if !model.isQwen && !model.isSraVaani && !model.isSpecialized && !model.isNemotron {
                fatalError("Missing Parakeet decoding configuration")
            }
        }
        // S1-mini raw framing and model identification
        guard DictationS1Polisher.isS1Mini("hf.co/superwhisper/s1-mini-gguf:Q4_K_M") else {
            fatalError("Failed to identify S1-mini Ollama registry tag")
        }
        guard DictationS1Polisher.isS1Mini("superwhisper/s1-mini-gguf") else {
            fatalError("Failed to identify S1-mini short name")
        }
        guard !DictationS1Polisher.isS1Mini("llama3.2:3b") else {
            fatalError("Incorrectly identified llama3.2 as S1-mini")
        }

        let rawPrompt = DictationS1Polisher.makeRawPrompt(
            systemPrompt: DictationS1Settings.systemPrompt,
            userMessage: "[Styling: semi-formal] [Structure: prose] [Context: general]\nhello world"
        )
        guard rawPrompt.contains("<|im_start|>assistant\n<think>\n\n</think>\n\n") else {
            fatalError("Raw prompt must contain closed empty think block to resolve unclosed thinking tag in GGUF template")
        }
        guard rawPrompt.contains("<|im_start|>system\n\(DictationS1Settings.systemPrompt)<|im_end|>\n") else {
            fatalError("Raw prompt must contain framed system prompt")
        }
        guard rawPrompt.contains("<|im_start|>user\n[Styling: semi-formal] [Structure: prose] [Context: general]\nhello world<|im_end|>\n") else {
            fatalError("Raw prompt must contain framed user message with control line")
        }

        let normalizedURL = DictationS1Polisher.normalizedBaseURL(URL(string: "http://127.0.0.1:51143/v1/chat/completions")!)
        check(normalizedURL.absoluteString, "http://127.0.0.1:51143")

        check(DictationS1Downloader.defaultModelID, "hf.co/superwhisper/s1-mini-gguf:Q4_K_M")

        // S1-mini direct GGUF and llama-server manager verification
        if let ggufModel = DictationLlamaServerManager.resolveGGUFModel() {
            guard FileManager.default.fileExists(atPath: ggufModel.path) else {
                fatalError("Resolved GGUF model path does not exist on disk")
            }
        }
        guard DictationLlamaServerManager.defaultPort == 51143 else {
            fatalError("Default port for llama-server should be 51143")
        }

        // S1-mini idle release verification
        guard DictationS1Settings.default.idleRelease == .tenMinutes else {
            fatalError("Default S1 idle release should be 10 minutes")
        }
        DictationLlamaServerManager.shared.setIdleRelease(.never)
        guard DictationLlamaServerManager.shared.currentIdleRelease == .never else {
            fatalError("Failed to set idle release to never")
        }
        DictationLlamaServerManager.shared.setIdleRelease(.fiveMinutes)
        guard DictationLlamaServerManager.shared.currentIdleRelease == .fiveMinutes else {
            fatalError("Failed to set idle release to 5 minutes")
        }

        // Speech Backtracking / Repairs
        check(DictationTextFormatter.resolveBacktracks("let's meet at 4, actually make that 5"), "5")
        check(DictationTextFormatter.resolveBacktracks("let's do Tuesday, scratch that, Wednesday"), "Wednesday")
        check(DictationTextFormatter.resolveBacktracks("call John, sorry I mean Sarah"), "Sarah")

        // Context-Aware App Style Routing
        check(AppStyleRouter.category(for: "com.tinyspeck.slackmacgap").rawValue, "workMessaging")
        check(AppStyleRouter.category(for: "net.whatsapp.WhatsApp").rawValue, "personalMessaging")
        check(AppStyleRouter.category(for: "com.apple.mail").rawValue, "email")
        check(AppStyleRouter.category(for: "com.microsoft.VSCode").rawValue, "code")
        check(AppStyleRouter.applyCategoryFormatting("See you soon.", bundleID: "net.whatsapp.WhatsApp"), "See you soon")

        // Transforms Store
        check(String(DictationTransform.defaultTransforms.count), "6")
        guard DictationTransform.defaultTransforms.contains(where: { $0.name == "Prompt Engineer" }) else {
            fatalError("Prompt Engineer transform should be in default transforms")
        }
        let tempTransformsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-transforms.json")
        let transformStore = DictationTransformStore(fileURL: tempTransformsURL)
        check(String(transformStore.allTransforms.count), "6")

        // Rich Text RTF Generation for Markdown
        let sampleMD = "Hello **world**, this is *italic* and `code`"
        if let attr = try? NSAttributedString(markdown: sampleMD, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            let rtf = try? attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            guard let rtf, rtf.count > 100 else {
                fatalError("Failed to produce RTF bytes for markdown snippet")
            }
        }

        // 14-Day Audio WAV Cache Export
        let tempWAVURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-sample.wav")
        defer { try? FileManager.default.removeItem(at: tempWAVURL) }
        let sampleFloats: [Float] = [0.0, 0.25, -0.25, 0.5, -0.5]
        DictationHistoryStore.writeWAV(samples: sampleFloats, to: tempWAVURL)
        guard FileManager.default.fileExists(atPath: tempWAVURL.path) else {
            fatalError("DictationHistoryStore.writeWAV failed to write audio file")
        }
        guard let wavBytes = try? Data(contentsOf: tempWAVURL), wavBytes.count == 44 + sampleFloats.count * 2 else {
            fatalError("WAV file byte length mismatch")
        }

        print("Dictation text formatting passed")
    }
}
