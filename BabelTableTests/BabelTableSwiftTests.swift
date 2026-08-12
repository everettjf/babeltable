import Testing
@testable import BabelTable

@Suite("BabelTable resilience")
struct BabelTableSwiftTests {
    @Test("Weak network retries remain bounded") @MainActor
    func boundedReconnect() {
        let error = TranslationError(raw: "network connection lost")
        #expect(TranslationCoordinator.reconnectDecision(afterCompletedAttempts: 0, error: error) == .retry(attempt: 1, delay: 1))
        #expect(TranslationCoordinator.reconnectDecision(afterCompletedAttempts: 3, error: error) == .fail)
    }
}
