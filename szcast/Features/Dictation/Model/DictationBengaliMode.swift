import Foundation

public enum DictationBengaliMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off = "off"
    case s1MiniPrompt = "s1MiniPrompt"
    case avroPhonetic = "avroPhonetic"
    case indicFlex = "indicFlex"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off:
            return String(localized: "Off (Bengali Script)")
        case .s1MiniPrompt:
            return String(localized: "S1-mini LLM (Conversational Banglish)")
        case .avroPhonetic:
            return String(localized: "Avro Engine (Deterministic 0ms)")
        case .indicFlex:
            return String(localized: "Indic-Flex (Direct Speech Model)")
        }
    }

    public var summary: String {
        switch self {
        case .off:
            return String(localized: "Output raw Bengali Unicode script (e.g. কেমন আছো).")
        case .s1MiniPrompt:
            return String(localized: "Local S1-mini daemon transliterates colloquial speech to Banglish.")
        case .avroPhonetic:
            return String(localized: "Instant 0ms rule-based phonetic engine converts to Latin characters.")
        case .indicFlex:
            return String(localized: "Direct acoustic Canary model emits Romanized Banglish without transliteration pass.")
        }
    }
}
