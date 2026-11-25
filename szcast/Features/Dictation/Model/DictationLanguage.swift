import Foundation

enum DictationLanguage: String, CaseIterable, Identifiable, Sendable {
    case arabic = "Arabic", bengali = "Bengali", cantonese = "Cantonese", chinese = "Chinese", czech = "Czech"
    case danish = "Danish", dutch = "Dutch", english = "English", filipino = "Filipino"
    case finnish = "Finnish", french = "French", german = "German", greek = "Greek"
    case hindi = "Hindi", hungarian = "Hungarian", indonesian = "Indonesian", italian = "Italian"
    case japanese = "Japanese", korean = "Korean", macedonian = "Macedonian", malay = "Malay"
    case persian = "Persian", polish = "Polish", portuguese = "Portuguese", romanian = "Romanian"
    case russian = "Russian", spanish = "Spanish", swedish = "Swedish", thai = "Thai"
    case turkish = "Turkish", vietnamese = "Vietnamese"

    var id: Self { self }

    /// The raw value is what the model is prompted with; the picker shows the reader's own name.
    func displayName(locale: Locale) -> String { locale.localizedString(forLanguageCode: code) ?? rawValue }

    /// BCP-47 locale tag for on-device live preview recognition.
    var previewLocaleIdentifier: String {
        switch self {
        case .arabic: "ar-SA"
        case .bengali: "bn-BD"
        case .cantonese: "zh-HK"
        case .chinese: "zh-CN"
        case .czech: "cs-CZ"
        case .danish: "da-DK"
        case .dutch: "nl-NL"
        case .english: "en-US"
        case .filipino: "fil-PH"
        case .finnish: "fi-FI"
        case .french: "fr-FR"
        case .german: "de-DE"
        case .greek: "el-GR"
        case .hindi: "hi-IN"
        case .hungarian: "hu-HU"
        case .indonesian: "id-ID"
        case .italian: "it-IT"
        case .japanese: "ja-JP"
        case .korean: "ko-KR"
        case .macedonian: "mk-MK"
        case .malay: "ms-MY"
        case .persian: "fa-IR"
        case .polish: "pl-PL"
        case .portuguese: "pt-BR"
        case .romanian: "ro-RO"
        case .russian: "ru-RU"
        case .spanish: "es-ES"
        case .swedish: "sv-SE"
        case .thai: "th-TH"
        case .turkish: "tr-TR"
        case .vietnamese: "vi-VN"
        }
    }

    /// Resolves a stored language preference (`rawValue`, BCP-47 identifier, or `nil` for auto).
    static func previewLocale(for settingValue: String?, current: Locale = .current) -> Locale {
        guard let trimmed = settingValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return current
        }
        if let language = Self(rawValue: trimmed) {
            return Locale(identifier: language.previewLocaleIdentifier)
        }
        return Locale(identifier: trimmed)
    }

    private var code: String {
        switch self {
        case .arabic: "ar"
        case .bengali: "bn"
        case .cantonese: "yue"
        case .chinese: "zh"
        case .czech: "cs"
        case .danish: "da"
        case .dutch: "nl"
        case .english: "en"
        case .filipino: "fil"
        case .finnish: "fi"
        case .french: "fr"
        case .german: "de"
        case .greek: "el"
        case .hindi: "hi"
        case .hungarian: "hu"
        case .indonesian: "id"
        case .italian: "it"
        case .japanese: "ja"
        case .korean: "ko"
        case .macedonian: "mk"
        case .malay: "ms"
        case .persian: "fa"
        case .polish: "pl"
        case .portuguese: "pt"
        case .romanian: "ro"
        case .russian: "ru"
        case .spanish: "es"
        case .swedish: "sv"
        case .thai: "th"
        case .turkish: "tr"
        case .vietnamese: "vi"
        }
    }
}
