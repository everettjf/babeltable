import XCTest
@testable import BabelTable

/// Covers the recently-added error classification that the home-screen alert,
/// the auto-reconnect decision, and the diagnostics log all depend on.
@MainActor final class TranslationErrorTests: XCTestCase {

    // MARK: - Classification by structured server code (preferred path)

    func testQuotaCodes() {
        XCTAssertEqual(TranslationError(message: "anything", code: "insufficient_quota").kind, .quota)
        XCTAssertEqual(TranslationError(message: "anything", code: "billing_hard_limit_reached").kind, .quota)
        // Code matching is case-insensitive.
        XCTAssertEqual(TranslationError(message: "x", code: "INSUFFICIENT_QUOTA").kind, .quota)
        // Generic substring fallback inside the code branch.
        XCTAssertEqual(TranslationError(message: "x", code: "some_quota_thing").kind, .quota)
    }

    func testAuthCodes() {
        XCTAssertEqual(TranslationError(message: "x", code: "invalid_api_key").kind, .auth)
        XCTAssertEqual(TranslationError(message: "x", code: "invalid_authentication").kind, .auth)
        // invalid_request_error counts as auth only when the message mentions the API key.
        XCTAssertEqual(TranslationError(message: "Incorrect API key provided", code: "invalid_request_error").kind, .auth)
        XCTAssertEqual(TranslationError(message: "x", code: "some_api_key_problem").kind, .auth)
        XCTAssertEqual(TranslationError(message: "x", code: "authentication_failed").kind, .auth)
    }

    func testRateLimitCodes() {
        XCTAssertEqual(TranslationError(message: "x", code: "rate_limit_exceeded").kind, .rateLimit)
        XCTAssertEqual(TranslationError(message: "x", code: "rate_limit_whatever").kind, .rateLimit)
    }

    /// A structured code must win even when the message text would classify
    /// differently — this is the whole point of the "classify by code" change.
    func testCodeTakesPrecedenceOverMisleadingMessage() {
        // Message mentions "api key" but the code says quota → quota wins.
        XCTAssertEqual(TranslationError(message: "your api key ran out", code: "insufficient_quota").kind, .quota)
        // Message mentions "rate limit" but code says auth → auth wins.
        XCTAssertEqual(TranslationError(message: "rate limit hit", code: "invalid_api_key").kind, .auth)
    }

    /// invalid_request_error without an API-key mention is not auth; it falls
    /// through code matching and then message matching.
    func testInvalidRequestErrorWithoutApiKeyFallsThrough() {
        XCTAssertEqual(TranslationError(message: "something totally generic", code: "invalid_request_error").kind, .unknown)
    }

    // MARK: - Classification by message text (client-side errors, no code)

    func testQuotaFromMessage() {
        XCTAssertEqual(TranslationError(raw: "You exceeded your current quota").kind, .quota)
        XCTAssertEqual(TranslationError(raw: "billing limit reached").kind, .quota)
    }

    func testAuthFromMessage() {
        XCTAssertEqual(TranslationError(raw: "Invalid API key").kind, .auth)
        XCTAssertEqual(TranslationError(raw: "401 Unauthorized").kind, .auth)
        XCTAssertEqual(TranslationError(raw: "authentication error").kind, .auth)
    }

    func testRateLimitFromMessage() {
        XCTAssertEqual(TranslationError(raw: "Rate limit reached for requests").kind, .rateLimit)
        XCTAssertEqual(TranslationError(raw: "HTTP 429 too many requests").kind, .rateLimit)
    }

    func testConnectionFromMessage() {
        XCTAssertEqual(TranslationError(raw: "Socket is not connected").kind, .connection)
        XCTAssertEqual(TranslationError(raw: "send failed").kind, .connection)
        XCTAssertEqual(TranslationError(raw: "The request timed out").kind, .connection)
        XCTAssertEqual(TranslationError(raw: "No internet connection").kind, .connection)
    }

    func testMicrophoneFromMessage() {
        XCTAssertEqual(TranslationError(raw: "Microphone unavailable").kind, .microphone)
        XCTAssertEqual(TranslationError(raw: "audio session failed").kind, .microphone)
        XCTAssertEqual(TranslationError(raw: "permission denied").kind, .microphone)
    }

    func testUnknownMessage() {
        XCTAssertEqual(TranslationError(raw: "the printer is on fire").kind, .unknown)
    }

    // MARK: - isRecoverable drives whether auto-reconnect kicks in

    func testRecoverableKinds() {
        XCTAssertTrue(TranslationError(message: "x", code: "rate_limit_exceeded").isRecoverable)
        XCTAssertTrue(TranslationError(raw: "Socket is not connected").isRecoverable)
    }

    func testNonRecoverableKinds() {
        XCTAssertFalse(TranslationError(message: "x", code: "insufficient_quota").isRecoverable)
        XCTAssertFalse(TranslationError(message: "x", code: "invalid_api_key").isRecoverable)
        XCTAssertFalse(TranslationError(raw: "Microphone unavailable").isRecoverable)
        XCTAssertFalse(TranslationError(raw: "the printer is on fire").isRecoverable)
    }

    // MARK: - Recovery action shown in the alert

    func testQuotaRecoveryOpensBilling() {
        let err = TranslationError(message: "x", code: "insufficient_quota")
        XCTAssertEqual(err.recovery, .openURL(URL(string: "https://platform.openai.com/account/billing")!))
        XCTAssertEqual(err.recoveryTitle, "Open billing")
    }

    func testAuthRecoveryOpensSettings() {
        let err = TranslationError(message: "x", code: "invalid_api_key")
        XCTAssertEqual(err.recovery, .openSettings)
        XCTAssertEqual(err.recoveryTitle, "Open Settings")
    }

    func testTransientKindsHaveNoRecoveryAction() {
        XCTAssertEqual(TranslationError(raw: "Socket is not connected").recovery, .none)
        XCTAssertEqual(TranslationError(message: "x", code: "rate_limit_exceeded").recovery, .none)
    }

    /// The unknown case is the only one that surfaces the raw server text to the
    /// user; the classified cases use a fixed, plain-language message.
    func testUnknownPreservesRawMessage() {
        let raw = "weird backend explosion 0xDEADBEEF"
        XCTAssertEqual(TranslationError(raw: raw).message, raw)
    }

    func testClassifiedCasesUseFixedMessageNotRawText() {
        let err = TranslationError(message: "raw server gibberish", code: "insufficient_quota")
        XCTAssertFalse(err.message.contains("gibberish"))
        XCTAssertEqual(err.title, "Out of OpenAI credit")
    }
}
