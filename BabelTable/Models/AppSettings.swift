import Foundation
import Observation

enum DisplayMode: String, Codable, Sendable, CaseIterable {
    /// Two panels stacked, top one rotated 180° for the person sitting opposite.
    case faceToFace
    /// Single chronological chat list — both readers sit side by side.
    case chat

    var displayName: String {
        switch self {
        case .faceToFace: return "Face-to-face (across the table)"
        case .chat: return "Same screen (chat style)"
        }
    }
}

/// Whether iOS should auto-balance levels between near and far speakers.
enum AutoLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case on

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off (raw audio)"
        case .on: return "On (balance speakers)"
        }
    }

    var detail: String {
        switch self {
        case .off: return "Highest fidelity. Best when one person speaks at a steady distance."
        case .on: return "Levels out volume between near and far speakers. Recommended for two-person use."
        }
    }
}

/// How utterances are tagged in the transcript: by their language, or by a
/// name for the person speaking ("You" / "Them").
enum SpeakerLabelStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case language
    case speaker

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .language: return "Language"
        case .speaker: return "Speaker name"
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    private enum Keys {
        static let primaryLanguage = "primaryLanguage"
        static let secondaryLanguage = "secondaryLanguage"
        static let displayMode = "displayMode"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let autoLevel = "autoLevel"
        static let speakerLabelStyle = "speakerLabelStyle"
        static let primarySpeakerName = "primarySpeakerName"
        static let secondarySpeakerName = "secondarySpeakerName"
    }

    var primaryLanguageCode: String {
        didSet { defaults.set(primaryLanguageCode, forKey: Keys.primaryLanguage) }
    }

    var secondaryLanguageCode: String {
        didSet { defaults.set(secondaryLanguageCode, forKey: Keys.secondaryLanguage) }
    }

    var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var autoLevel: AutoLevel {
        didSet { defaults.set(autoLevel.rawValue, forKey: Keys.autoLevel) }
    }

    var speakerLabelStyle: SpeakerLabelStyle {
        didSet { defaults.set(speakerLabelStyle.rawValue, forKey: Keys.speakerLabelStyle) }
    }

    /// Name for the person reading the primary (your) language.
    var primarySpeakerName: String {
        didSet { defaults.set(primarySpeakerName, forKey: Keys.primarySpeakerName) }
    }

    /// Name for the person reading the secondary (other) language.
    var secondarySpeakerName: String {
        didSet { defaults.set(secondarySpeakerName, forKey: Keys.secondarySpeakerName) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.primaryLanguageCode = defaults.string(forKey: Keys.primaryLanguage) ?? "en"
        self.secondaryLanguageCode = defaults.string(forKey: Keys.secondaryLanguage) ?? "zh"
        let modeRaw = defaults.string(forKey: Keys.displayMode) ?? DisplayMode.chat.rawValue
        self.displayMode = DisplayMode(rawValue: modeRaw) ?? .chat
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        let levelRaw = defaults.string(forKey: Keys.autoLevel) ?? AutoLevel.on.rawValue
        self.autoLevel = AutoLevel(rawValue: levelRaw) ?? .on

        let styleRaw = defaults.string(forKey: Keys.speakerLabelStyle) ?? SpeakerLabelStyle.language.rawValue
        self.speakerLabelStyle = SpeakerLabelStyle(rawValue: styleRaw) ?? .language
        self.primarySpeakerName = defaults.string(forKey: Keys.primarySpeakerName) ?? "You"
        self.secondarySpeakerName = defaults.string(forKey: Keys.secondarySpeakerName) ?? "Them"
    }

    var primaryLanguage: Language {
        SupportedLanguages.byCode(primaryLanguageCode) ?? SupportedLanguages.outputs[0]
    }

    var secondaryLanguage: Language {
        SupportedLanguages.byCode(secondaryLanguageCode) ?? SupportedLanguages.outputs[1]
    }

}
