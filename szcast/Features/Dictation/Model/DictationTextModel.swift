import Foundation

/// Lightweight local GGUF text models runnable via the bundled `llama-server` daemon.
enum DictationTextModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case s1Mini = "s1-mini"
    case smolLM2 = "smollm2-360m"
    case qwen25Small = "qwen2.5-0.5b"
    case qwen3Small = "qwen3-0.6b"
    case llama32OneB = "llama-3.2-1b"
    case gemma3OneB = "gemma-3-1b"

    var id: Self { self }

    var title: String {
        switch self {
        case .s1Mini: "S1-mini 1.0"
        case .smolLM2: "SmolLM2 360M Instruct"
        case .qwen25Small: "Qwen 2.5 0.5B Instruct"
        case .qwen3Small: "Qwen 3 0.6B"
        case .llama32OneB: "Llama 3.2 1B Instruct"
        case .gemma3OneB: "Gemma 3 1B IT"
        }
    }

    var quantizationBadge: String {
        switch self {
        case .s1Mini, .qwen25Small, .gemma3OneB: "Q4_K_M"
        case .smolLM2, .qwen3Small: "Q8_0"
        case .llama32OneB: "Q4_0"
        }
    }

    var summary: String {
        switch self {
        case .s1Mini:
            String(localized: "Purpose-built for ultra-fast speech cleanup, grammar, and formatting.")
        case .smolLM2:
            String(localized: "HuggingFaceTB smallest fast instruct model under 400 MB.")
        case .qwen25Small:
            String(localized: "Lightweight multilingual instruct model for clean rewrites.")
        case .qwen3Small:
            String(localized: "Compact multilingual reasoning & instruction model.")
        case .llama32OneB:
            String(localized: "Meta 1B instruction-tuned model for higher quality polishing.")
        case .gemma3OneB:
            String(localized: "Google 1B lightweight text generation and cleanup model.")
        }
    }

    var approximateMegabytes: Int {
        switch self {
        case .smolLM2: 369
        case .s1Mini: 462
        case .qwen25Small: 469
        case .qwen3Small: 610
        case .llama32OneB: 737
        case .gemma3OneB: 769
        }
    }

    var expectedBytes: Int64 {
        switch self {
        case .s1Mini: 484_219_808
        case .smolLM2: 386_404_992
        case .qwen25Small: 491_400_032
        case .qwen3Small: 639_446_688
        case .llama32OneB: 773_025_920
        case .gemma3OneB: 806_058_240
        }
    }

    var fileName: String {
        switch self {
        case .s1Mini: "s1-mini-1.0.gguf"
        case .smolLM2: "smollm2-360m-instruct-q8_0.gguf"
        case .qwen25Small: "qwen2.5-0.5b-instruct-q4_k_m.gguf"
        case .qwen3Small: "Qwen3-0.6B-Q8_0.gguf"
        case .llama32OneB: "Llama-3.2-1B-Instruct-Q4_0.gguf"
        case .gemma3OneB: "gemma-3-1b-it-Q4_K_M.gguf"
        }
    }

    var downloadURLs: [URL] {
        switch self {
        case .s1Mini:
            return [
                URL(string: "https://github.com/sauravsz/szcast/releases/download/v1.1.2/s1-mini-1.0.gguf")!,
                URL(string: "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/34add00a48a2e5d24e5a4ee5405a99620a3a240c/s1-mini-q4_k_m.gguf")!
            ]
        case .smolLM2:
            return [
                URL(string: "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/593b5a2e04c817629873d720312d426166341fb2/smollm2-360m-instruct-q8_0.gguf")!
            ]
        case .qwen25Small:
            return [
                URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/9217f5db79a26e29c3a764c977c090e388390f51/qwen2.5-0.5b-instruct-q4_k_m.gguf")!
            ]
        case .qwen3Small:
            return [
                URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/23749fefcc7285fd17c5192f6c19e10cb2b16e89/Qwen3-0.6B-Q8_0.gguf")!
            ]
        case .llama32OneB:
            return [
                URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/067b946cf014fc8e75f9f31d99735f8a22f3c882/Llama-3.2-1B-Instruct-Q4_0.gguf")!
            ]
        case .gemma3OneB:
            return [
                URL(string: "https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/f9c28bcd8573b91ef8e7db4f3622111270ed6765/gemma-3-1b-it-Q4_K_M.gguf")!
            ]
        }
    }
}
