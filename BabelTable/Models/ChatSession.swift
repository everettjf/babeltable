import Foundation

struct TranscriptLine: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var timestamp: Date
    var languageCode: String
    var text: String
    /// Whether this line is the source (auto-detected) transcription
    /// from the input mic, or a translated output.
    var kind: Kind

    enum Kind: String, Codable, Sendable {
        case input    // recognized speech in detected source language
        case output   // translated output in the configured target language
    }
}

/// One utterance in chat-mode display: what was said and the translation.
struct ChatTurn: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var startedAt: Date
    var sourceLanguageCode: String
    var sourceText: String
    var translatedLanguageCode: String
    /// Raw machine translation streamed from gpt-realtime-translate.
    var translatedText: String
    /// Optional context-aware refinement of `translatedText` produced after the
    /// turn closes. Nil until (and unless) refinement runs and succeeds.
    /// Optional so older archived turns still decode.
    var refinedText: String?

    /// The translation to show: the refined version when available, else the
    /// raw machine translation.
    var bestTranslation: String {
        if let refinedText, !refinedText.isEmpty { return refinedText }
        return translatedText
    }

    /// True once a refinement has been applied — drives the ✨ marker in the UI.
    var isRefined: Bool { (refinedText?.isEmpty == false) }
}

struct ChatSession: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date?
    var primaryLanguageCode: String
    var secondaryLanguageCode: String
    /// Transcript lines for primary panel (translations into primaryLanguage,
    /// plus optional input lines).
    var primaryLines: [TranscriptLine]
    /// Transcript lines for secondary panel (translations into secondaryLanguage).
    var secondaryLines: [TranscriptLine]
    /// Chronological chat-mode turns (auto-detected source + matching translation).
    /// Optional so older archived sessions still decode.
    var chatTurns: [ChatTurn]?

    var displayTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startedAt)
    }

    var durationDescription: String {
        guard let endedAt else { return "—" }
        let elapsed = endedAt.timeIntervalSince(startedAt)
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
