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

/// Where the microphone sits relative to speakers.
enum MicScenario: String, Codable, Sendable, CaseIterable, Identifiable {
    case closeSingle
    case desktopTwo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .closeSingle: return "Close, single speaker"
        case .desktopTwo: return "Across a table, two speakers"
        }
    }

    var detail: String {
        switch self {
        case .closeSingle: return "Phone held close to one person."
        case .desktopTwo: return "Phone on a table between both people."
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

/// Desired register for the refined translation. `auto` lets the model match
/// the source; the others nudge it toward casual or formal forms (tu/vous,
/// です/ます, 你/您, etc.).
enum Formality: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto
    case casual
    case formal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Match the speaker"
        case .casual: return "Casual"
        case .formal: return "Formal / polite"
        }
    }

    /// Instruction fragment fed to the refinement model. Empty for `.auto`.
    var promptClause: String {
        switch self {
        case .auto: return ""
        case .casual: return "Use a casual, informal register (e.g. informal pronouns and verb forms)."
        case .formal: return "Use a formal, polite register (e.g. formal pronouns and honorific verb forms)."
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    private let defaults: UserDefaults
    private let keychain: KeychainStore

    private enum Keys {
        static let aiConsent = "aiConsentVersion"
        static let primaryLanguage = "primaryLanguage"
        static let secondaryLanguage = "secondaryLanguage"
        static let displayMode = "displayMode"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let micScenario = "micScenario"
        static let autoLevel = "autoLevel"
        static let speakerLabelStyle = "speakerLabelStyle"
        static let primarySpeakerName = "primarySpeakerName"
        static let secondarySpeakerName = "secondarySpeakerName"
        static let refineEnabled = "refineEnabled"
        static let formality = "formality"
        static let glossaryText = "glossaryText"
    }

    static let currentConsentVersion = 1
    var aiConsentVersion: Int {
        didSet { defaults.set(aiConsentVersion, forKey: Keys.aiConsent) }
    }
    var hasAIConsent: Bool { aiConsentVersion == Self.currentConsentVersion }

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

    var micScenario: MicScenario {
        didSet { defaults.set(micScenario.rawValue, forKey: Keys.micScenario) }
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

    /// Run a context-aware text refinement pass over each finished turn.
    var refineEnabled: Bool {
        didSet { defaults.set(refineEnabled, forKey: Keys.refineEnabled) }
    }

    var formality: Formality {
        didSet { defaults.set(formality.rawValue, forKey: Keys.formality) }
    }

    /// User glossary, one rule per line as "source => target". Terms the
    /// translator should render a specific way, or proper nouns to keep verbatim.
    var glossaryText: String {
        didSet { defaults.set(glossaryText, forKey: Keys.glossaryText) }
    }

    /// Backing store for `hasAPIKey`. The Keychain-backed `apiKey` computed
    /// property cannot be tracked by Observation, so views key off this
    /// stored property instead — it updates whenever the key is set.
    private(set) var hasAPIKey: Bool

    var apiKey: String { keychain.apiKey ?? "" }

    func saveAPIKey(_ value: String) throws {
        try keychain.save(value)
        hasAPIKey = !(keychain.apiKey ?? "").isEmpty
    }

    func deleteAPIKey() throws {
        try keychain.deleteAPIKey()
        hasAPIKey = false
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = .shared) {
        self.defaults = defaults
        self.keychain = keychain
        self.aiConsentVersion = defaults.integer(forKey: Keys.aiConsent)
        self.primaryLanguageCode = defaults.string(forKey: Keys.primaryLanguage) ?? "en"
        self.secondaryLanguageCode = defaults.string(forKey: Keys.secondaryLanguage) ?? "zh"
        let modeRaw = defaults.string(forKey: Keys.displayMode) ?? DisplayMode.chat.rawValue
        self.displayMode = DisplayMode(rawValue: modeRaw) ?? .chat
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        let scenarioRaw = defaults.string(forKey: Keys.micScenario) ?? MicScenario.desktopTwo.rawValue
        self.micScenario = MicScenario(rawValue: scenarioRaw) ?? .desktopTwo

        let levelRaw = defaults.string(forKey: Keys.autoLevel) ?? AutoLevel.on.rawValue
        self.autoLevel = AutoLevel(rawValue: levelRaw) ?? .on

        let styleRaw = defaults.string(forKey: Keys.speakerLabelStyle) ?? SpeakerLabelStyle.language.rawValue
        self.speakerLabelStyle = SpeakerLabelStyle(rawValue: styleRaw) ?? .language
        self.primarySpeakerName = defaults.string(forKey: Keys.primarySpeakerName) ?? "You"
        self.secondarySpeakerName = defaults.string(forKey: Keys.secondarySpeakerName) ?? "Them"

        // Default off; `object(forKey:)` distinguishes "never set" from an
        // explicit false so a returning user's choice is respected.
        self.refineEnabled = (defaults.object(forKey: Keys.refineEnabled) as? Bool) ?? false
        let formalityRaw = defaults.string(forKey: Keys.formality) ?? Formality.auto.rawValue
        self.formality = Formality(rawValue: formalityRaw) ?? .auto
        self.glossaryText = defaults.string(forKey: Keys.glossaryText) ?? ""
        self.hasAPIKey = !(keychain.apiKey ?? "").isEmpty
    }

    var primaryLanguage: Language {
        SupportedLanguages.byCode(primaryLanguageCode) ?? SupportedLanguages.outputs[0]
    }

    var secondaryLanguage: Language {
        SupportedLanguages.byCode(secondaryLanguageCode) ?? SupportedLanguages.outputs[1]
    }

    /// Parsed glossary rules: (source, target) pairs from `glossaryText`.
    /// Accepts "a => b" or "a = b"; blank and malformed lines are skipped.
    var glossaryRules: [(source: String, target: String)] {
        glossaryText.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let separator = line.contains("=>") ? "=>" : "="
            let parts = line.components(separatedBy: separator)
            guard parts.count == 2 else { return nil }
            let source = parts[0].trimmingCharacters(in: .whitespaces)
            let target = parts[1].trimmingCharacters(in: .whitespaces)
            guard !source.isEmpty, !target.isEmpty else { return nil }
            return (source, target)
        }
    }
}
