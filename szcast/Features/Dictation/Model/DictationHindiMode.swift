import Foundation

public enum DictationHindiMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off = "off"
    case s1MiniPrompt = "s1MiniPrompt"
    case phoneticEngine = "phoneticEngine"
    case whisperApex = "whisperApex"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off:
            return String(localized: "Off (Hindi Devanagari Script)")
        case .s1MiniPrompt:
            return String(localized: "S1-mini LLM (Conversational Hinglish)")
        case .phoneticEngine:
            return String(localized: "Phonetic Engine (Deterministic 0ms)")
        case .whisperApex:
            return String(localized: "Whisper-Apex (Direct Speech Model)")
        }
    }

    public var summary: String {
        switch self {
        case .off:
            return String(localized: "Output raw Hindi Devanagari script (e.g. आप कैसे हैं).")
        case .s1MiniPrompt:
            return String(localized: "Local S1-mini daemon transliterates colloquial speech to Hinglish.")
        case .phoneticEngine:
            return String(localized: "Instant 0ms rule-based phonetic engine converts to Latin characters.")
        case .whisperApex:
            return String(localized: "Direct acoustic Whisper model emits conversational Hinglish without transliteration pass.")
        }
    }
}
