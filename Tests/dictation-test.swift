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
            if model.isAppleSpeech {
                guard model.components.isEmpty, model.repository.isEmpty, model.approximateInstalledMegabytes == 0 else {
                    fatalError("Built-in Apple SpeechAnalyzer metadata should not require HuggingFace download")
                }
            } else {
                guard !model.components.isEmpty, model.revision.count == 40,
                    model.requiredFiles.isSuperset(of: model.components)
                else {
                    fatalError("Model installation metadata is incomplete")
                }
            }
            if let configuration = model.parakeetConfiguration {
                let expectedBlank = model == .v2 ? 1024 : 8192
                guard (model.family == .parakeet || model.family == .sravaani),
                    configuration.blankToken == expectedBlank,
                    configuration.encoderUsesGPU == (model == .redux),
                    model.components.contains(configuration.joint + ".mlmodelc")
                else {
                    fatalError("Parakeet download and inference disagree")
                }
            } else if !model.isQwen && !model.isSraVaani && !model.isSpecialized && !model.isNemotron && !model.isParakeetCTC && !model.isAppleSpeech {
                fatalError("Missing Parakeet decoding configuration")
            }
        }
        guard DictationTextModel.allCases.count == 6,
              DictationTextModel.smolLM2.approximateMegabytes < 400
        else {
            fatalError("Lightweight local text model catalog incomplete")
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

        // DictationLanguage live-preview locale resolution
        let fallbackLocale = Locale(identifier: "fr-FR")
        check(DictationLanguage.previewLocale(for: nil, current: fallbackLocale).identifier, "fr-FR")
        check(DictationLanguage.previewLocale(for: "Chinese", current: fallbackLocale).identifier, "zh-CN")
        check(DictationLanguage.previewLocale(for: "Cantonese", current: fallbackLocale).identifier, "zh-HK")
        check(DictationLanguage.previewLocale(for: "English", current: fallbackLocale).identifier, "en-US")
        check(DictationLanguage.previewLocale(for: "es-MX", current: fallbackLocale).identifier, "es-MX")

        // Cached Dictionary & Snippet rules invalidate cleanly across mutations
        let cachedWordsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-cached-words.json")
        let cachedSnippetsURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-cached-snippets.json")
        defer {
            try? FileManager.default.removeItem(at: cachedWordsURL)
            try? FileManager.default.removeItem(at: cachedSnippetsURL)
        }
        let dictStore = DictationDictionaryStore(fileURL: cachedWordsURL, snippetsFileURL: cachedSnippetsURL)
        dictStore.addWord(canonical: "PostgreSQL", aliases: ["post gres"])
        check(dictStore.applyDictionaryAndPacks("we run post gres daily"), "we run PostgreSQL daily")
        dictStore.addWord(canonical: "Kubernetes", aliases: ["kube"])
        check(dictStore.applyDictionaryAndPacks("deploy kube on post gres"), "deploy Kubernetes on PostgreSQL")
        if let kubeID = dictStore.words.first(where: { $0.canonical == "Kubernetes" })?.id {
            dictStore.removeWord(id: kubeID)
        }
        check(dictStore.applyDictionaryAndPacks("deploy kube on post gres"), "deploy kube on PostgreSQL")
        dictStore.addSnippet(keyword: "my sig", expansion: "Best, Sz")
        check(dictStore.applySnippets("Thanks, my sig"), "Thanks, Best, Sz")

        // Phonetic dictionary recovery + anti-false-insertion guard
        dictStore.addWord(canonical: "Shubham")
        dictStore.addWord(canonical: "XcodeGen")
        dictStore.addWord(canonical: "SDK")
        dictStore.addWord(canonical: "MCP")
        dictStore.addWord(canonical: "Point of Sale")
        dictStore.addWord(canonical: "App Store")
        check(dictStore.applyDictionaryAndPacks("Ask Subham to update ex code gen"), "Ask Shubham to update XcodeGen")
        check(dictStore.applyDictionaryAndPacks("Use the s d k for m c p and open point off sale on ap store"), "Use the SDK for MCP and open Point of Sale on App Store")
        check(dictStore.applyDictionaryAndPacks("Their thinking about working today and the house"), "Their thinking about working today and the house")
        let hints = dictStore.promptVocabularyHint(for: "Ask Subham about PostgreSQL", maxTerms: 10)
        assertTrue(hints.contains("Shubham") && hints.contains("PostgreSQL"), "Vocabulary prompt hint prioritizes matching terms")

        // New AI/ML + Finance packs, CSV import, plain-text export & window context vocabulary extraction
        store.enabledPacks = Set(VocabularyPackType.allCases)
        check(String(store.loadedTermsCount(for: .aiMl)), "16")
        check(String(store.loadedTermsCount(for: .finance)), "16")
        check(store.applyDictionaryAndPacks("Train with pie torch and check ebita plus wacc"), "Train with PyTorch and check EBITDA plus WACC")
        let csvCount = dictStore.importFromText("Supabase, supa base, soopabase\nFastAPI, fast api")
        assertTrue(csvCount == 2, "CSV hotword import parses canonical and aliases")
        check(dictStore.applyDictionaryAndPacks("Deploy fast api on supa base"), "Deploy FastAPI on Supabase")
        let contextSymbols = DictationDictionaryStore.extractContextVocabulary(
            fromWindowTitle: "DictationCoordinator.swift — szcast (SDK)")
        assertTrue(
            contextSymbols.contains("DictationCoordinator.swift") && contextSymbols.contains("SDK"),
            "Window title symbol extractor surfaces filenames and uppercase acronyms"
        )
        assertTrue(
            DictationModel.recommended(forLanguage: "English", physicalMemoryBytes: 32 * 1_073_741_824) == .ultra,
            "32GB Mac recommends Parakeet Ultra"
        )
        assertTrue(
            DictationModel.recommended(forLanguage: "Hinglish", physicalMemoryBytes: 8 * 1_073_741_824) == .whisperApex,
            "Hinglish recommends Whisper Apex"
        )

        // Whisper hallucination & repetition loop suppression
        check(DictationTextFormatter.stripHallucinations("Thank you for watching."), "")
        check(DictationTextFormatter.stripHallucinations("Deploy it tonight. Thanks for watching!"), "Deploy it tonight.")
        check(
            DictationTextFormatter.stripHallucinations("We shipped v2. We shipped v2. We shipped v2."),
            "We shipped v2."
        )

        // ISO language code resolution + unified code-switching prompt
        assertTrue(DictationLanguage.isoCode(for: "English") == "en", "English maps to en")
        assertTrue(DictationLanguage.isoCode(for: "Hindi") == "hi", "Hindi maps to hi")
        assertTrue(DictationLanguage.isoCode(for: "auto") == nil, "auto omits explicit language")
        let codeSwitchSettings = DictationS1Settings(
            enabled: true, tone: .semiFormal, structure: .prose, context: .general, hindiMode: .s1MiniPrompt
        )
        let prompt = codeSwitchSettings.effectiveSystemPrompt(for: "meeting 5 बजे hai")
        assertTrue(prompt.contains("Hinglish") && prompt.contains("restarts"), "Hindi S1 prompt preserves speech repair and code-switching")
        let userMsg = DictationS1Settings.normalizedUserMessage(
            controlLine: codeSwitchSettings.controlLine,
            transcript: "test",
            vocabularyTerms: ["Shubham"]
        )
        assertTrue(
            userMsg.contains("[Vocabulary: Shubham]") && !userMsg.contains("[Preceding text"),
            "Normalized user message embeds vocabulary hints without leaking surrounding text"
        )

        // Deterministic Hinglish & Banglish phonetic converters (schwa insertion + word-boundary protection)
        check(HinglishPhoneticConverter.convert("नमस्ते कमल।"), "namaste kamal.")
        check(HinglishPhoneticConverter.convert("यह काम करना है"), "yah kam karna hai")
        check(HinglishPhoneticConverter.convert("sky John"), "sky John")
        check(
            HinglishPhoneticConverter.normalizeIfNeeded(
                "आप कैसे हैं", hindiMode: .off, isCloud: false, localModel: .sravaani
            ),
            "aap kaise hain"
        )
        check(
            HinglishPhoneticConverter.normalizeIfNeeded(
                "आप कैसे हैं", hindiMode: .off, isCloud: false, localModel: .redux
            ),
            "आप कैसे हैं"
        )
        check(AvroPhoneticConverter.convert("আমি ভালো আছি, কেমন?"), "ami bhalo achhi, kemon?")
        check(AvroPhoneticConverter.convert("কাজ করতে যাচ্ছি।"), "kaj korte jachchhi.")
        check(AvroPhoneticConverter.convert("ধন্যবাদ, sky John"), "dhonyobad, sky John")
        check(
            AvroPhoneticConverter.normalizeIfNeeded(
                "আমি ভালো আছি", bengaliMode: .off, isCloud: false, localModel: .sravaani
            ),
            "ami bhalo achhi"
        )
        check(
            AvroPhoneticConverter.normalizeIfNeeded(
                "আমি ভালো আছি", bengaliMode: .off, isCloud: false, localModel: .indicFlex
            ),
            "ami bhalo achhi"
        )
        check(
            AvroPhoneticConverter.normalizeIfNeeded(
                "আমি ভালো আছি", bengaliMode: .off, isCloud: false, localModel: .redux
            ),
            "আমি ভালো আছি"
        )

        // Wispr-style brackets, symbols, slashes, Roman numerals & structural formatting
        check(
            DictationTextFormatter.convertSpokenPunctuation("it is a bracket start hello world bracket close"),
            "it is (hello world)"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("open square bracket alpha close square bracket"),
            "[alpha]"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("curly bracket start key colon value curly bracket close"),
            "{key: value}"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("input forward slash output"),
            "input/output"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("column slash row and yes / no"),
            "column/row and yes/no"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("path backslash folder"),
            "path\\folder"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("my underscore var at the rate domain dot com"),
            "my_var @domain dot com"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("dollar sign 50 and 25 percent sign and hashtag ai"),
            "$50 and 25% and #ai"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("he said open quote stay focused close quote"),
            "he said \"stay focused\""
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("it's column one and roman numeral one and roman numeral two"),
            "it's Column I and I and II"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("column number two with roman numeral to and roman numeral IV"),
            "Column II with II and IV"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("numeral four bullet point all caps urgent task"),
            "4\n- URGENT task"
        )

        // Fast-path clean-speech bypass & model-aware prompting
        let cleanProseSettings = DictationS1Settings(
            enabled: true, tone: .semiFormal, structure: .prose, context: .general
        )
        assertTrue(
            !DictationS1Settings.needsLLMCleanup(
                "Principle of self-awareness, self-control, and duty-oriented action. Emotional regulation.",
                s1Settings: cleanProseSettings
            ),
            "Clean short prose skips LLM round-trip (<1ms)"
        )
        assertTrue(
            DictationS1Settings.needsLLMCleanup("Wait no, send it to Sarah instead", s1Settings: cleanProseSettings),
            "Mid-sentence repair triggers LLM cleanup"
        )
        assertTrue(
            DictationS1Settings.needsLLMCleanup("Meeting at 5 बजे hai", s1Settings: codeSwitchSettings),
            "Native Devanagari triggers Hinglish transliteration pass"
        )
        assertTrue(
            !DictationS1Settings.needsLLMCleanup("Meeting at 5 pm today", s1Settings: codeSwitchSettings),
            "Pure ASCII skips Indic LLM pass"
        )
        let nonS1Prompt = DictationS1Settings.normalizedUserMessage(
            controlLine: cleanProseSettings.controlLine,
            transcript: "Column I",
            vocabularyTerms: ["szcast"],
            isS1Mini: false
        )
        assertTrue(
            !nonS1Prompt.contains("[Styling:") && nonS1Prompt.contains("Transcript:\nColumn I"),
            "Non-S1 instruct models avoid raw S1 control-tag headers"
        )

        // Expanded Wispr symbols, comma-wrapped filler removal, auto-lists, voice submit, code style, auto-learn & provider routing
        check(
            DictationTextFormatter.convertSpokenPunctuation(
                "copyright symbol registered trademark trademark symbol section sign division sign multiplication sign plus minus sign greater than sign less than sign"
            ),
            "© ® ™ § ÷ × ± > <"
        )
        check(
            DictationTextFormatter.removeFillerWords("Well, you know, we should ship it."),
            "Well we should ship it."
        )
        check(
            DictationTextFormatter.formatSpokenEnumerations("First buy milk. Second write tests. Third ship code."),
            "1. Buy milk.\n2. Write tests.\n3. Ship code."
        )
        check(
            DictationTextFormatter.formatSpokenEnumerations("First, let me explain."),
            "First, let me explain."
        )
        let submitPositive = DictationTextFormatter.extractTrailingSubmitCommand("Send update, press enter.")
        assertTrue(
            submitPositive.shouldSubmit && submitPositive.text == "Send update",
            "Trailing voice submit extracts command cleanly"
        )
        let submitNegative = DictationTextFormatter.extractTrailingSubmitCommand("Don't press enter yet")
        assertTrue(
            !submitNegative.shouldSubmit && submitNegative.text == "Don't press enter yet",
            "Negated submit phrase is preserved untouched"
        )
        check(
            AppStyleRouter.applyCategoryFormatting("git status.", bundleID: "com.microsoft.VSCode"),
            "git status"
        )
        check(
            AppStyleRouter.applyCategoryFormatting("First line.\nSecond line.", bundleID: "com.microsoft.VSCode"),
            "First line.\nSecond line."
        )
        let learnedSingle = DictationDictionaryStore.detectEditedWordPair(
            original: "Saurab built szcast today.",
            edited: "Saurav built szcast today."
        )
        assertTrue(
            learnedSingle?.original == "Saurab" && learnedSingle?.corrected == "Saurav",
            "Single-word post-edit detects dictionary correction pair"
        )
        assertTrue(
            DictationDictionaryStore.detectEditedWordPair(
                original: "Alpha beta gamma.",
                edited: "Delta epsilon gamma."
            ) == nil,
            "Multi-word edits do not trigger false dictionary auto-learn"
        )
        assertTrue(
            DictationPolishProvider.resolved(preferred: .groq, groqAPIKey: "") == .localS1,
            "Groq without API key resolves back to localS1"
        )
        assertTrue(
            DictationPolishProvider.resolved(preferred: .appleIntelligence, groqAPIKey: "") == .appleIntelligence,
            "Apple Intelligence resolves directly when selected"
        )

        // Phase 3: Sentence-scoped backtrack, stutter collapse, ITN, list continuation, syntax commands, browser routing & diff circuit breaker
        check(
            DictationTextFormatter.resolveBacktracks("Meet at 3pm. Call John, sorry I mean Sarah."),
            "Meet at 3pm. Sarah."
        )
        check(
            DictationTextFormatter.collapseRepetitions("b-b-because wh-what we re-enter by e-mail"),
            "because what we re-enter by e-mail"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("version one point two point three"),
            "v1.2.3"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("Meet at three fifteen pm for forty five percent"),
            "Meet at 3:15 PM for 45%"
        )
        check(
            DictationTextFormatter.convertSpokenPunctuation("Email john dot doe at gmail dot com"),
            "Email john.doe@gmail.com"
        )
        check(
            DictationTextFormatter.format("- first item", context: Context(before: "- existing\n- ", after: "")),
            "First item"
        )
        check(
            DictationTextFormatter.format("1. third item\n2. fourth item", context: Context(before: "1. a\n2. b\n3. ", after: "")),
            "Third item\n4. fourth item"
        )
        check(
            DictationTextFormatter.format("docs", context: Context(before: "https://", after: "")),
            "docs"
        )
        check(
            DictationTextFormatter.formatSyntaxCommands(
                "heading two Release Notes\ntask item Verify build\nwiki link Architecture",
                isCodeContext: false,
                isNotesContext: true
            ),
            "## Release Notes\n- [ ] Verify build\n[[Architecture]]"
        )
        check(
            DictationTextFormatter.formatSyntaxCommands(
                "camel case user id triple equals constant case max retries and dash dash verbose in tilde slash dot env",
                isCodeContext: true,
                isNotesContext: false
            ),
            "userId === MAX_RETRIES and --verbose in ~/.env"
        )
        assertTrue(
            DictationTextFormatter.extractVoiceMetaCommand("Undo that.") == .undoLast
                && DictationTextFormatter.extractVoiceMetaCommand("Select all") == .selectAll
                && DictationTextFormatter.extractVoiceMetaCommand("Copy that!") == .copyThat
                && DictationTextFormatter.extractVoiceMetaCommand("Open new tab") == .newTab
                && DictationTextFormatter.extractVoiceMetaCommand("Please undo that edit in the second paragraph") == nil,
            "Standalone voice meta-commands match cleanly without false positives"
        )
        assertTrue(
            DictationTextFormatter.extractAskAIQuery("Ask AI: what is the capital of Japan?") == "what is the capital of Japan?"
                && DictationTextFormatter.extractAskAIQuery("I will ask AI later") == nil,
            "Ask AI prefix extracts explicit queries without triggering mid-sentence"
        )
        assertTrue(
            AppStyleRouter.category(for: "com.google.Chrome", windowTitle: "Fix #42 · Pull Request", documentURL: "https://github.com/org/repo/pull/42") == .code
                && AppStyleRouter.category(for: "com.apple.Safari", windowTitle: "Inbox", documentURL: "https://mail.google.com/mail/u/0/#inbox") == .email
                && AppStyleRouter.category(for: "org.keepassxc.keepassxc", windowTitle: "github.com", documentURL: "https://github.com") == .general,
            "Browser URL/title routing detects code/email while strictly redacting credential apps"
        )
        assertTrue(
            DictationS1Settings.isSafePolishEdit(original: "Ship the release build at five today", candidate: "Ship the release build at 5 PM today.", structure: .prose)
                && !DictationS1Settings.isSafePolishEdit(original: "Ship the release build at five today please", candidate: "As an AI language model, I cannot assist with that.", structure: .prose)
                && !DictationS1Settings.isSafePolishEdit(original: "One two three four five six seven eight", candidate: "One.", structure: .prose)
                && !DictationS1Settings.isSafePolishEdit(original: "Ship clean build", candidate: "Here is a huge greeting 🎉 " + String(repeating: "extra words ", count: 20), structure: .prose),
            "LLM diff circuit breaker rejects chatty preambles, truncations, and explosive prose hallucinations"
        )

        // Phase 4: Apostrophe-insensitive echo strip, cursor marker extraction & pill positions
        check(
            DictationTextFormatter.stripEcho("launch's status, tomorrow", after: "about the launch’s status"),
            " tomorrow"
        )
        let cursorParen = DictationTextFormatter.extractCursorMarker(from: "foo(|)bar")
        assertTrue(
            cursorParen.text == "foobar" && cursorParen.cursorOffsetFromEnd == 3,
            "Cursor marker (|) extracts exact end offset"
        )
        let cursorToken = DictationTextFormatter.extractCursorMarker(from: "hello {cursor}")
        assertTrue(
            cursorToken.text == "hello " && cursorToken.cursorOffsetFromEnd == nil,
            "Trailing {cursor} leaves nil offset at end of text"
        )

        // Phase 5: Hotword Precision/Recall Torture Suite & Mixed Punctuation/Backtrack Pipeline
        let tortureDir = FileManager.default.temporaryDirectory.appendingPathComponent("szcast-p5-\(UUID())")
        let tortureDict = DictationDictionaryStore(
            fileURL: tortureDir.appending(path: "words.json"),
            snippetsFileURL: tortureDir.appending(path: "snippets.json")
        )
        defer { try? FileManager.default.removeItem(at: tortureDir) }
        tortureDict.enabledPacks = Set(VocabularyPackType.allCases)
        for term in ["Kubernetes", "PostgreSQL", "LangGraph", "SDK", "API", "ROI", "Point of Sale", "App Store"] {
            tortureDict.addWord(canonical: term)
        }
        tortureDict.addWord(canonical: "SDK", aliases: ["ess dee kay"])
        tortureDict.addWord(canonical: "API", aliases: ["aye pee eye"])
        tortureDict.addWord(canonical: "szcast", aliases: ["sz cast", "s z cast"])
        let jargonExpectations: [(String, String)] = [
            ("kubernetis postgresgl pie torch langraff", "Kubernetes PostgreSQL PyTorch LangGraph"),
            ("ess dee kay m c p aye pee eye", "SDK MCP API"),
            ("e bit da wack roi g g u f", "EBITDA WACC ROI GGUF"),
            ("point of sail and app star using core m l for sz cast", "Point of Sale and App Store using CoreML for szcast"),
            ("common words stay normal in at on it is to as hello water light", "common words stay normal in at on it is to as hello water light"),
            ("I love this app", "I love this app")
        ]
        for (input, expected) in jargonExpectations {
            let actual = tortureDict.applyDictionaryAndPacks(input)
            check(actual, expected)
        }

        let tortureRaw = "Um, first item. Call John, sorry I mean Sarah at three fifteen pm, b-b-because version two point oh in bracket start column one bracket close."
        var tortureOut = DictationTextFormatter.stripHallucinations(tortureRaw)
        tortureOut = DictationTextFormatter.resolveBacktracks(tortureOut)
        tortureOut = DictationTextFormatter.collapseRepetitions(tortureOut)
        tortureOut = DictationTextFormatter.convertSpokenPunctuation(tortureOut)
        tortureOut = DictationTextFormatter.removeFillerWords(tortureOut)
        tortureOut = DictationTextFormatter.format(tortureOut, context: nil)
        check(
            tortureOut,
            "First item. Sarah at 3:15 PM, because v2.0 in (Column I). "
        )

        print("Dictation text formatting passed")
    }

    private static func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fatalError("Assertion failed: \(message)")
        }
    }
}
