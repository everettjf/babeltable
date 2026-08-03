import Foundation

/// A user-facing translation/connection failure: a title, a plain-language
/// explanation, and an optional recovery action shown in the home-screen alert.
///
/// Classification prefers the OpenAI error `code`/`type` (stable across wording
/// changes) and falls back to substring matching for client-side errors
/// (sockets, audio) that carry no structured code.
struct TranslationError: Equatable, Sendable {

    enum Kind: Equatable, Sendable {
        case quota
        case auth
        case rateLimit
        case connection
        case microphone
        case unknown
    }

    enum Recovery: Equatable, Sendable {
        case none
        case openSettings
        case openURL(URL)
    }

    let kind: Kind
    let title: String
    let message: String
    let recovery: Recovery
    let recoveryTitle: String?

    /// Build from a server error, preferring the structured `code`/`type`.
    init(message: String, code: String?) {
        self.init(kind: Self.classify(message: message, code: code), fallbackMessage: message)
    }

    /// Build from a client-side error string with no structured code
    /// (socket failures, audio-session errors, missing API key).
    init(raw: String) {
        self.init(message: raw, code: nil)
    }

    private init(kind: Kind, fallbackMessage: String) {
        self.kind = kind
        switch kind {
        case .quota:
            title = "Out of OpenAI credit"
            message = "Your OpenAI account has run out of quota. Add credit or upgrade your plan in the OpenAI billing page, then tap Start to try again."
            recovery = .openURL(URL(string: "https://platform.openai.com/account/billing")!)
            recoveryTitle = "Open billing"
        case .auth:
            title = "Check your API key"
            message = "BabelTable couldn't sign in to OpenAI. Open Settings and make sure your API key is entered correctly and is still active."
            recovery = .openSettings
            recoveryTitle = "Open Settings"
        case .rateLimit:
            title = "Too many requests"
            message = "OpenAI is rate-limiting your account right now. Wait a few seconds, then tap Start to try again."
            recovery = .none
            recoveryTitle = nil
        case .connection:
            title = "Connection lost"
            message = "The connection to the translation service dropped. Check your internet connection, then tap Start to reconnect."
            recovery = .none
            recoveryTitle = nil
        case .microphone:
            title = "Microphone unavailable"
            message = "BabelTable couldn't start the microphone. Check that microphone access is allowed in your device Settings, then tap Start to try again."
            recovery = .none
            recoveryTitle = nil
        case .unknown:
            title = "Translation error"
            message = fallbackMessage
            recovery = .none
            recoveryTitle = nil
        }
    }

    /// True for failures a reconnect could plausibly recover from. Quota and
    /// auth are persistent and should fail fast; connection drops and rate
    /// limits are transient and worth retrying.
    var isRecoverable: Bool {
        switch kind {
        case .connection, .rateLimit: return true
        case .quota, .auth, .microphone, .unknown: return false
        }
    }

    private static func classify(message: String, code: String?) -> Kind {
        // Prefer the stable server code/type when present.
        if let code = code?.lowercased() {
            switch code {
            case "insufficient_quota", "billing_hard_limit_reached":
                return .quota
            case "invalid_api_key", "invalid_authentication":
                return .auth
            case "invalid_request_error" where message.lowercased().contains("api key"):
                return .auth
            case "rate_limit_exceeded":
                return .rateLimit
            default:
                break
            }
            if code.contains("quota") { return .quota }
            if code.contains("rate_limit") { return .rateLimit }
            if code.contains("api_key") || code.contains("authentication") { return .auth }
        }

        // Fall back to message text for client-side errors with no code.
        let text = message.lowercased()
        if text.contains("quota") || text.contains("billing") || text.contains("insufficient_quota") {
            return .quota
        }
        if text.contains("api key") || text.contains("apikey")
            || text.contains("invalid_api_key") || text.contains("incorrect api key")
            || text.contains("unauthorized") || text.contains("authentication")
            || text.contains("401") {
            return .auth
        }
        if text.contains("rate limit") || text.contains("rate_limit") || text.contains("429") {
            return .rateLimit
        }
        if text.contains("socket is not connected") || text.contains("send failed")
            || text.contains("receive failed") || text.contains("network")
            || text.contains("connection") || text.contains("offline")
            || text.contains("timed out") || text.contains("internet") {
            return .connection
        }
        if text.contains("microphone") || text.contains("audio") || text.contains("permission") {
            return .microphone
        }
        return .unknown
    }
}
