import Foundation

struct Language: Identifiable, Hashable, Codable, Sendable {
    let code: String
    let name: String
    let nativeName: String
    /// Representative flag emoji. A flag is a region, not a language, so these
    /// are pragmatic picks for at-a-glance recognition, not linguistic claims.
    let flag: String

    var id: String { code }

    /// Flag + native name, e.g. "🇨🇳 中文". The one label format used everywhere.
    var labeled: String { "\(flag) \(nativeName)" }
}

enum SupportedLanguages {
    // The 13 output languages supported by gpt-realtime-translate.
    static let outputs: [Language] = [
        Language(code: "en", name: "English", nativeName: "English", flag: "🇺🇸"),
        Language(code: "zh", name: "Chinese (Mandarin)", nativeName: "中文", flag: "🇨🇳"),
        Language(code: "es", name: "Spanish", nativeName: "Español", flag: "🇪🇸"),
        Language(code: "pt", name: "Portuguese", nativeName: "Português", flag: "🇵🇹"),
        Language(code: "fr", name: "French", nativeName: "Français", flag: "🇫🇷"),
        Language(code: "de", name: "German", nativeName: "Deutsch", flag: "🇩🇪"),
        Language(code: "it", name: "Italian", nativeName: "Italiano", flag: "🇮🇹"),
        Language(code: "ja", name: "Japanese", nativeName: "日本語", flag: "🇯🇵"),
        Language(code: "ko", name: "Korean", nativeName: "한국어", flag: "🇰🇷"),
        Language(code: "ru", name: "Russian", nativeName: "Русский", flag: "🇷🇺"),
        Language(code: "hi", name: "Hindi", nativeName: "हिन्दी", flag: "🇮🇳"),
        Language(code: "id", name: "Indonesian", nativeName: "Bahasa Indonesia", flag: "🇮🇩"),
        Language(code: "vi", name: "Vietnamese", nativeName: "Tiếng Việt", flag: "🇻🇳"),
    ]

    static func byCode(_ code: String) -> Language? {
        outputs.first { $0.code == code }
    }

    /// Normalize a raw code that may carry a script/region subtag
    /// (e.g. "zh-Hans" → "zh") to one of our base codes.
    static func normalize(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code))
    }

    /// The matching `Language`, tolerating subtagged codes like "zh-Hant".
    static func resolve(_ code: String) -> Language? {
        byCode(code) ?? byCode(normalize(code))
    }

    /// Human label for any code, including the sentinels used while a turn's
    /// source language is still unknown. Returns "🌐 …" for unknown/auto.
    static func label(forCode code: String) -> String {
        guard !code.isEmpty, code != "auto" else { return "🌐 …" }
        if let lang = resolve(code) { return lang.labeled }
        return "🏳️ \(normalize(code).uppercased())"
    }

    /// Native name only (no flag) for any code; "—" for unknown/auto.
    static func name(forCode code: String) -> String {
        guard !code.isEmpty, code != "auto" else { return "—" }
        return resolve(code)?.nativeName ?? normalize(code).uppercased()
    }

    /// English display name for prompting the refinement model.
    static func englishName(forCode code: String) -> String {
        resolve(code)?.name ?? normalize(code)
    }
}
