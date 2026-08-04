import XCTest
@testable import BabelTable

/// Covers the backoff schedule the auto-reconnect feature uses to decide how
/// long to wait before rebuilding the sockets after a transient failure.
@MainActor
final class ReconnectBackoffTests: XCTestCase {

    func testConnectionBackoffIsExponentialAndCapped() {
        // 1s, 2s, 4s, then capped at 8s.
        XCTAssertEqual(TranslationCoordinator.backoffDelay(forAttempt: 1, kind: .connection), 1)
        XCTAssertEqual(TranslationCoordinator.backoffDelay(forAttempt: 2, kind: .connection), 2)
        XCTAssertEqual(TranslationCoordinator.backoffDelay(forAttempt: 3, kind: .connection), 4)
        XCTAssertEqual(TranslationCoordinator.backoffDelay(forAttempt: 4, kind: .connection), 8)
        XCTAssertEqual(TranslationCoordinator.backoffDelay(forAttempt: 5, kind: .connection), 8)
        XCTAssertEqual(TranslationCoordinator.backoffDelay(forAttempt: 99, kind: .connection), 8)
    }

    func testRateLimitUsesFixedLongerDelay() {
        // Rate limits get a flat 5s regardless of attempt — retrying sooner
        // just re-trips the limit.
        XCTAssertEqual(TranslationCoordinator.backoffDelay(forAttempt: 1, kind: .rateLimit), 5)
        XCTAssertEqual(TranslationCoordinator.backoffDelay(forAttempt: 3, kind: .rateLimit), 5)
    }

    func testWeakNetworkRetriesThreeTimesThenSurfacesFailure() {
        let error = TranslationError(raw: "network connection lost")
        XCTAssertEqual(
            TranslationCoordinator.reconnectDecision(afterCompletedAttempts: 0, error: error),
            .retry(attempt: 1, delay: 1)
        )
        XCTAssertEqual(
            TranslationCoordinator.reconnectDecision(afterCompletedAttempts: 1, error: error),
            .retry(attempt: 2, delay: 2)
        )
        XCTAssertEqual(
            TranslationCoordinator.reconnectDecision(afterCompletedAttempts: 2, error: error),
            .retry(attempt: 3, delay: 4)
        )
        XCTAssertEqual(
            TranslationCoordinator.reconnectDecision(afterCompletedAttempts: 3, error: error),
            .fail
        )
    }

    func testAuthenticationFailureDoesNotRetry() {
        let error = TranslationError(message: "invalid API key", code: "invalid_api_key")
        XCTAssertEqual(
            TranslationCoordinator.reconnectDecision(afterCompletedAttempts: 0, error: error),
            .fail
        )
    }
}
