import Foundation

@main
struct DictationTest {
    static func main() {
        let locale = Locale(identifier: "en_US")
        func check(_ actual: String, _ expected: String) {
            guard actual == expected else {
                print("Expected \(expected.debugDescription), got \(actual.debugDescription)")
                exit(1)
            }
        }

        typealias Context = DictationTextFormatter.Context
        check(DictationTextFormatter.format("  Hello. \n", context: nil), "Hello.")
        check(DictationTextFormatter.format("hello", context: Context(before: "", after: "")), "Hello")
        check(DictationTextFormatter.format("World", context: Context(before: "Hello", after: "")), " world")
        check(DictationTextFormatter.format("world", context: Context(before: "Hello.", after: "")), " World")
        check(DictationTextFormatter.format("hello", context: Context(before: "Wait. ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("hello", context: Context(before: "Wait\n  ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("World", context: Context(before: "Hello ", after: "again")),
            "world ")
        check(DictationTextFormatter.format("hello", context: Context(before: "(", after: ")")), "hello")
        check(
            DictationTextFormatter.format("application", context: Context(before: "l’", after: "")),
            "application")
        check(
            DictationTextFormatter.format(
                "szcast", context: Context(before: "Use", after: "again"),
                adaptCapitalization: false), " szcast ")
        check(
            DictationTextFormatter.format(
                "world", context: Context(before: "Hello.", after: ""),
                adaptCapitalization: false), " world")
        check(
            DictationTextFormatter.format(
                "hello", context: Context(before: "", after: ""),
                adaptCapitalization: false), "hello")
        check(
            DictationTextFormatter.format(
                "World.", context: Context(before: "Hello ", after: ")"),
                adaptCapitalization: false), "World.")
        let document = "prefix. Text to replace suffix"
        check(
            DictationTextFormatter.format(
                "world",
                context: Context(
                    before: document.prefix(7), after: document.suffix(6))), " World ")
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

        // Filler words removal
        check(DictationTextFormatter.removeFillerWords("Um, this is uh a test"), "this is a test")

        // S1 Control Line
        let s1 = DictationS1Settings(enabled: true, tone: .formal, structure: .lists, context: .email)
        check(s1.controlLine, "[Styling: formal] [Structure: lists] [Context: email]")

        // Vocabulary Packs
        check(VocabularyPackType.tech.displayName, "Tech")
        guard VocabularyPackType.tech.fixesCount == 76 else {
            fatalError("Tech vocabulary pack should have 76 fixes")
        }
        guard VocabularyPackType.medical.fixesCount == 87 else {
            fatalError("Medical vocabulary pack should have 87 fixes")
        }

        check(DictationModel.redux.folderName, "parakeet-redux")
        check(DictationModel.ultra.folderName, "parakeet-ultra")
        check(DictationModel.redux.title, "Parakeet · Redux")
        check(DictationModel.ultra.title, "Parakeet · Ultra")
        check(DictationIdleRelease.allCases.map(\.rawValue).description, "[0, 1, 2, 5, 10, 15, 20, 30, 60]")
        check(DictationIdleRelease.never.title(locale: locale), "Never")
        check(DictationIdleRelease.oneHour.title(locale: locale), "1 hour")
        check(DictationIdleRelease.oneHour.title(locale: Locale(identifier: "fr_FR")), "1\u{00a0}heure")
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
                guard model.family == .parakeet, configuration.blankToken == 8192,
                    configuration.encoderUsesGPU == (model == .redux),
                    model.components.contains(configuration.joint + ".mlmodelc")
                else {
                    fatalError("Parakeet download and inference disagree")
                }
            } else if !model.isQwen {
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

        let normalizedURL = DictationS1Polisher.normalizedBaseURL(URL(string: "http://localhost:11434/v1/chat/completions")!)
        check(normalizedURL.absoluteString, "http://localhost:11434")

        check(DictationS1Downloader.defaultModelID, "hf.co/superwhisper/s1-mini-gguf:Q4_K_M")

        print("Dictation text formatting passed")
    }
}
