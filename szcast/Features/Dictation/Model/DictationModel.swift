import Foundation

enum DictationModel: String, CaseIterable, Identifiable, Codable, Sendable {
    struct ParakeetConfiguration: Sendable {
        let joint: String
        let blankToken: Int
        let encoderUsesGPU: Bool
    }
    enum Family: String, CaseIterable, Identifiable {
        case parakeet = "Parakeet", nemotron = "Nemotron", qwen = "Qwen", sravaani = "SraVaani", specialized = "Specialized"
        var id: Self { self }
        var summary: String {
            switch self {
            case .parakeet:
                return String(localized: "Fast and memory-efficient")
            case .nemotron:
                return String(localized: "NVIDIA cache-aware streaming Conformer-RNNT")
            case .qwen:
                return String(localized: "More languages, but slower")
            case .sravaani:
                return String(localized: "65+ Indian languages offline")
            case .specialized:
                return String(localized: "Direct phonetic Romanization (Hinglish & Banglish)")
            }
        }
    }
    case redux
    case ultra
    case v2 = "parakeet-tdt-0.6b-v2"
    case ctc = "parakeet-ctc-0.6b"
    case ctcSmall = "parakeet-ctc-110m"
    case nemotron = "nemotron-0.6b"
    case qwenSmall = "qwen-0.6b"
    case qwenLarge = "qwen-1.7b"
    case sravaani = "sravaani-1.0"
    case whisperApex = "whisper-apex"
    case indicFlex = "indic-flex"

    var id: Self { self }
    var title: String { "\(family.rawValue) · \(variantTitle)" }
    var variantTitle: String {
        switch self {
        case .ultra: "Ultra"
        case .redux: "Redux"
        case .v2: "TDT v2 (EN)"
        case .ctc: "CTC 0.6B (EN)"
        case .ctcSmall: "CTC 110M (Tiny)"
        case .nemotron: "0.6B Streaming"
        case .qwenSmall: "0.6B"
        case .qwenLarge: "1.7B"
        case .sravaani: "1.0 (Indic TDT)"
        case .whisperApex: "Hinglish Apex"
        case .indicFlex: "Banglish Flex"
        }
    }

    var summary: String {
        switch self {
        case .redux: String(localized: "Lightweight and efficient.")
        case .ultra: String(localized: "Higher accuracy, larger download.")
        case .v2: String(localized: "English FastConformer-TDT (600M, 6.02% WER, CC-BY-4.0).")
        case .ctc: String(localized: "Fast English FastConformer-CTC (600M, INT8 CoreML, CC-BY-4.0).")
        case .ctcSmall: String(localized: "Lightweight 110M English Conformer-CTC (~102 MB).")
        case .nemotron: String(localized: "Cache-aware streaming English ASR optimized for Apple Neural Engine.")
        case .qwenSmall: String(localized: "Smaller and faster.")
        case .qwenLarge: String(localized: "Higher accuracy, more memory.")
        case .sravaani: String(localized: "IISc/ARTPARK CoreML FastConformer-TDT for Indic languages and English.")
        case .whisperApex: String(localized: "Oriserve Whisper Large-v3-Turbo emitting direct phonetic Hinglish.")
        case .indicFlex: String(localized: "Bodhan AI Canary-1B emitting direct Romanized Banglish.")
        }
    }

    var family: Family {
        switch self {
        case .ultra, .redux, .v2, .ctc, .ctcSmall: .parakeet
        case .nemotron: .nemotron
        case .qwenSmall, .qwenLarge: .qwen
        case .sravaani: .sravaani
        case .whisperApex, .indicFlex: .specialized
        }
    }
    var isNemotron: Bool { family == .nemotron }
    var isQwen: Bool { family == .qwen }
    var isSraVaani: Bool { family == .sravaani }
    var isSpecialized: Bool { family == .specialized }
    var isParakeetCTC: Bool { self == .ctc || self == .ctcSmall }

    var parakeetConfiguration: ParakeetConfiguration? {
        switch self {
        case .ultra, .redux:
            return .init(joint: "JointDecisionv3", blankToken: 8192, encoderUsesGPU: self == .redux)
        case .v2:
            return .init(joint: "JointDecision", blankToken: 1024, encoderUsesGPU: false)
        case .ctc, .ctcSmall, .sravaani, .nemotron, .whisperApex, .indicFlex, .qwenSmall, .qwenLarge:
            return nil
        }
    }
    var coverage: String {
        switch self {
        case .ultra, .redux: String(localized: "25 languages")
        case .v2, .ctc, .ctcSmall: String(localized: "English")
        case .nemotron: String(localized: "English (1120ms streaming)")
        case .qwenSmall, .qwenLarge: String(localized: "30 languages and 22 Chinese dialects")
        case .sravaani: String(localized: "65 Indian languages and English")
        case .whisperApex: String(localized: "Hindi & Conversational Hinglish")
        case .indicFlex: String(localized: "Bengali (Banglish) & 22 Indic Languages")
        }
    }
    var folderName: String {
        switch self {
        case .ultra, .redux: "parakeet-\(rawValue)"
        case .v2, .ctc, .ctcSmall: rawValue
        case .nemotron: "nemotron-speech-streaming-en-0.6b-coreml"
        case .qwenSmall, .qwenLarge: rawValue
        case .sravaani: "sravaani-1.0"
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
        case .v2:
            return ["parakeet-tdt-0.6b-v2", "parakeet-tdt-0.6b-v2-coreml"]
        case .ctc:
            return ["parakeet-ctc-0.6b", "parakeet-ctc-0.6b-coreml"]
        case .ctcSmall:
            return ["parakeet-ctc-110m", "parakeet-ctc-110m-coreml"]
        case .nemotron:
            return ["nemotron-speech-streaming-en-0.6b-coreml", "nemotron-0.6b"]
        case .qwenSmall:
            return ["qwen-0.6b", "Qwen3-ASR-0.6B-CoreML-INT8"]
        case .qwenLarge:
            return ["qwen-1.7b", "Qwen3-ASR-1.7B-CoreML-INT8"]
        case .sravaani:
            return ["sravaani-1.0", "sravaani-1.0-coreml", "SraVaani-1.0-CoreML", "SraVaani-1.0"]
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
        case .v2: 464
        case .ctc: 600
        case .ctcSmall: 102
        case .nemotron: 610
        case .qwenSmall: 940
        case .qwenLarge: 2352
        case .sravaani: 892
        case .whisperApex: 825
        case .indicFlex: 1220
        }
    }

    var components: Set<String> {
        switch self {
        case .ultra, .redux, .v2:
            guard let configuration = parakeetConfiguration else { return [] }
            return [
                "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc",
                configuration.joint + ".mlmodelc", "parakeet_vocab.json"
            ]
        case .ctc:
            return ["MelSpectrogram_int8.mlmodelc", "AudioEncoder_int8.mlmodelc", "vocab.json"]
        case .ctcSmall:
            return ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "vocab.json"]
        case .nemotron:
            return [
                "nemotron_coreml_1120ms/preprocessor.mlmodelc",
                "nemotron_coreml_1120ms/encoder/encoder_int8.mlmodelc",
                "nemotron_coreml_1120ms/decoder.mlmodelc",
                "nemotron_coreml_1120ms/joint.mlmodelc",
                "nemotron_coreml_1120ms/metadata.json"
            ]
        case .qwenSmall, .qwenLarge:
            return ["encoder.mlmodelc", "decoder.mlmodelc", "embedding.mlmodelc", "config.json"]
        case .sravaani:
            return ["SraVaaniEncoder.mlmodelc", "SraVaaniDecoder.mlmodelc", "tokenizer.model"]
        case .whisperApex:
            return ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "config.json"]
        case .indicFlex:
            return [
                "int8/indic_flex_preprocessor.mlpackage",
                "int8/indic_flex_encoder.mlpackage",
                "int8/indic_flex_decoder_stateful.mlpackage",
                "int8/metadata.json"
            ]
        }
    }

    var requiredFiles: Set<String> {
        switch self {
        case .ultra, .redux, .v2, .ctc, .ctcSmall:
            return components
        case .nemotron:
            return components.union(["nemotron_coreml_1120ms/tokenizer.json"])
        case .qwenSmall, .qwenLarge:
            return components.union(["vocab.json", "merges.txt"])
        case .sravaani:
            return components.union(["config.json"])
        case .whisperApex:
            return components.union(["vocab.json", "merges.txt"])
        case .indicFlex:
            return components.union(["int8/vocab.json", "int8/tokenizer_config.json"])
        }
    }

    var repository: String {
        switch self {
        case .ultra, .redux: "FluidInference/\(folderName)-coreml"
        case .v2: "FluidInference/parakeet-tdt-0.6b-v2-coreml"
        case .ctc: "FluidInference/parakeet-ctc-0.6b-coreml"
        case .ctcSmall: "FluidInference/parakeet-ctc-110m-coreml"
        case .nemotron: "FluidInference/nemotron-speech-streaming-en-0.6b-coreml"
        case .qwenSmall: "UniMocha/Qwen3-ASR-0.6B-CoreML-INT8"
        case .qwenLarge: "UniMocha/Qwen3-ASR-1.7B-CoreML-INT8"
        case .sravaani: "spashii/SraVaani-1.0-CoreML"
        case .whisperApex: "kumargaurav9013/whisper-hindi2hinglish-apex-coreml"
        case .indicFlex: "sookie90/indic-transcribe-flex-coreml"
        }
    }

    var revision: String {
        switch self {
        case .ultra: "95eaa59a39d4394f047a4dc5cce480388a60d1b6"
        case .redux: "8c5ef97a29cd120dc76b354b3f22b7fec3b486f9"
        case .v2: "ee09c569f73759e6d44c9bd16766f477b2b36d39"
        case .ctc: "c5e129ca09f50759e3025eca7609f68485fa09a7"
        case .ctcSmall: "accdafd8cf8a2ff1cabe3c11e54416b405d409aa"
        case .nemotron: "0651794847e50f9687bcaa096c3f8ec696ac6fc4"
        case .qwenSmall: "27b7a26835d7c2cd1cf774b4c490eb5519ca71a0"
        case .qwenLarge: "06312fbac1383cd22e1000c28b017634e03251a2"
        case .sravaani: "3f3daa338ee3f25c878fc6863d96943959cc14a9"
        case .whisperApex: "668ef2d23517d6f3da41622aff6b46089e466104"
        case .indicFlex: "c7bf7a566a555083466399b0c9072db2202486a1"
        }
    }
}
