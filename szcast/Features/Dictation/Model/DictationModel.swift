import Foundation

enum DictationModel: String, CaseIterable, Identifiable, Codable, Sendable {
    struct ParakeetConfiguration: Sendable {
        let joint: String
        let blankToken: Int
        let encoderUsesGPU: Bool
    }
    enum Family: String, CaseIterable, Identifiable {
        case parakeet = "Parakeet", qwen = "Qwen", sravaani = "SraVaani", specialized = "Specialized"
        var id: Self { self }
        var summary: String {
            switch self {
            case .parakeet:
                return String(localized: "Fast and memory-efficient")
            case .qwen:
                return String(localized: "More languages, but slower")
            case .sravaani:
                return String(localized: "65+ Indian languages and live streaming")
            case .specialized:
                return String(localized: "Direct phonetic Romanization (Hinglish & Banglish)")
            }
        }
    }
    case redux
    case ultra
    case qwenSmall = "qwen-0.6b"
    case qwenLarge = "qwen-1.7b"
    case sravaani = "sravaani-1.0"
    case sravaaniLive = "sravaani-0.5-live"
    case whisperApex = "whisper-apex"
    case indicFlex = "indic-flex"

    var id: Self { self }
    var title: String { "\(family.rawValue) · \(variantTitle)" }
    var variantTitle: String {
        switch self {
        case .ultra: "Ultra"
        case .redux: "Redux"
        case .qwenSmall: "0.6B"
        case .qwenLarge: "1.7B"
        case .sravaani: "1.0 (65 Languages)"
        case .sravaaniLive: "0.5 Live (Streaming)"
        case .whisperApex: "Hinglish Apex"
        case .indicFlex: "Banglish Flex"
        }
    }

    var summary: String {
        switch self {
        case .redux: String(localized: "Lightweight and efficient.")
        case .ultra: String(localized: "Higher accuracy, larger download.")
        case .qwenSmall: String(localized: "Smaller and faster.")
        case .qwenLarge: String(localized: "Higher accuracy, more memory.")
        case .sravaani: String(localized: "IISc/ARTPARK FastConformer-TDT covering 65 Indic languages.")
        case .sravaaniLive: String(localized: "Low-latency streaming cache-aware FastConformer CTC for real-time dictation.")
        case .whisperApex: String(localized: "Oriserve Whisper Large-v3-Turbo emitting direct phonetic Hinglish.")
        case .indicFlex: String(localized: "Bodhan AI Canary-1B emitting direct Romanized Banglish.")
        }
    }

    var family: Family {
        switch self {
        case .ultra, .redux: .parakeet
        case .qwenSmall, .qwenLarge: .qwen
        case .sravaani, .sravaaniLive: .sravaani
        case .whisperApex, .indicFlex: .specialized
        }
    }
    var isQwen: Bool { family == .qwen }
    var isSraVaani: Bool { family == .sravaani }
    var isSpecialized: Bool { family == .specialized }

    var parakeetConfiguration: ParakeetConfiguration? {
        switch self {
        case .ultra, .redux:
            return .init(joint: "JointDecisionv3", blankToken: 8192, encoderUsesGPU: self == .redux)
        case .sravaani:
            return .init(joint: "JointDecisionv3", blankToken: 8192, encoderUsesGPU: true)
        case .sravaaniLive, .whisperApex, .indicFlex, .qwenSmall, .qwenLarge:
            return nil
        }
    }
    var coverage: String {
        switch self {
        case .ultra, .redux: String(localized: "25 languages")
        case .qwenSmall, .qwenLarge: String(localized: "30 languages and 22 Chinese dialects")
        case .sravaani: String(localized: "65 Indian languages and regional dialects")
        case .sravaaniLive: String(localized: "63 Indian languages (streaming)")
        case .whisperApex: String(localized: "Hindi & Conversational Hinglish")
        case .indicFlex: String(localized: "Bengali (Banglish) & 22 Indic Languages")
        }
    }
    var folderName: String {
        switch self {
        case .ultra, .redux: "parakeet-\(rawValue)"
        case .qwenSmall, .qwenLarge: rawValue
        case .sravaani: "sravaani-1.0"
        case .sravaaniLive: "sravaani-0.5-live"
        case .whisperApex: "whisper-hindi2hinglish-apex"
        case .indicFlex: "indic-transcribe-flex"
        }
    }
    var possibleFolderNames: [String] {
        switch self {
        case .ultra:
            return ["parakeet-ultra", "parakeet-ultra-coreml"]
        case .redux:
            return ["parakeet-redux", "parakeet-tdt-0.6b-v3", "parakeet-tdt-0.6b-v3-coreml"]
        case .qwenSmall:
            return ["qwen-0.6b", "Qwen3-ASR-0.6B-CoreML-INT8"]
        case .qwenLarge:
            return ["qwen-1.7b", "Qwen3-ASR-1.7B-CoreML-INT8"]
        case .sravaani:
            return ["sravaani-1.0", "sravaani-1.0-coreml", "SraVaani-1.0"]
        case .sravaaniLive:
            return ["sravaani-0.5-live", "sravaani-0.5-live-coreml", "SraVaani-0.5-live"]
        case .whisperApex:
            return ["whisper-hindi2hinglish-apex", "whisper-hindi2hinglish-apex-coreml"]
        case .indicFlex:
            return ["indic-transcribe-flex", "indic-transcribe-flex-coreml"]
        }
    }
    var approximateInstalledMegabytes: Int {
        switch self {
        case .ultra: 632
        case .redux: 220
        case .qwenSmall: 940
        case .qwenLarge: 2352
        case .sravaani: 920
        case .sravaaniLive: 510
        case .whisperApex: 1600
        case .indicFlex: 1250
        }
    }

    var components: Set<String> {
        switch self {
        case .ultra, .redux:
            guard let configuration = parakeetConfiguration else { return [] }
            return [
                "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
                configuration.joint + ".mlmodelc", "parakeet_vocab.json"
            ]
        case .qwenSmall, .qwenLarge:
            return ["encoder.mlmodelc", "decoder.mlmodelc", "embedding.mlmodelc", "config.json"]
        case .sravaani:
            return ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc", "parakeet_vocab.json"]
        case .sravaaniLive:
            return ["encoder.mlmodelc", "decoder.mlmodelc", "tokenizer.model"]
        case .whisperApex:
            return ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "config.json"]
        case .indicFlex:
            return ["encoder.mlmodelc", "decoder.mlmodelc", "tokenizer.json"]
        }
    }

    var requiredFiles: Set<String> {
        switch self {
        case .ultra, .redux:
            return components
        case .qwenSmall, .qwenLarge:
            return components.union(["vocab.json", "merges.txt"])
        case .sravaani:
            return components
        case .sravaaniLive:
            return components
        case .whisperApex:
            return components.union(["vocab.json", "merges.txt"])
        case .indicFlex:
            return components
        }
    }

    var repository: String {
        switch self {
        case .ultra, .redux: "FluidInference/\(folderName)-coreml"
        case .qwenSmall: "UniMocha/Qwen3-ASR-0.6B-CoreML-INT8"
        case .qwenLarge: "UniMocha/Qwen3-ASR-1.7B-CoreML-INT8"
        case .sravaani: "ARTPARK-IISc/SraVaani-1.0"
        case .sravaaniLive: "ARTPARK-IISc/SraVaani-0.5-live"
        case .whisperApex: "kumargaurav9013/whisper-hindi2hinglish-apex-coreml"
        case .indicFlex: "sookie90/indic-transcribe-flex-coreml"
        }
    }

    var revision: String {
        switch self {
        case .ultra: "95eaa59a39d4394f047a4dc5cce480388a60d1b6"
        case .redux: "8c5ef97a29cd120dc76b354b3f22b7fec3b486f9"
        case .qwenSmall: "27b7a26835d7c2cd1cf774b4c490eb5519ca71a0"
        case .qwenLarge: "06312fbac1383cd22e1000c28b017634e03251a2"
        case .sravaani: "a7254684e699e464fb70d10ad301e28fa0330cad"
        case .sravaaniLive: "29a15303a55673367134eee9e1d18cb1a2dcaabf"
        case .whisperApex: "f1cc87f9820d55650413305d00218343cb1d0da6"
        case .indicFlex: "c7bf7a566a555083466399b0c9072db2202486a1"
        }
    }
}
