import Translation
import XCTest
@testable import BabelTable

/// Installed-assets integration checks. Never download models or access the microphone from tests.
@MainActor
final class OfflineDeviceTests: XCTestCase {
    func testInstalledEnglishChineseModelsTranslateBothDirections() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Apple translation assets require a physical device.")
#else
        let pair = SessionLanguagePair(primary: "en", secondary: "zh")
        let status = await OfflineModels.status(for: pair)
        guard status == .ready else {
            throw XCTSkip("Prepare English and Chinese speech/translation models in Settings first. Current state: \(status)")
        }
        for (source, target, text) in [("en", "zh", "Good morning. Thank you for your help."),
                                       ("zh", "en", "早上好，谢谢你的帮助。") ] {
            let session = TranslationSession(installedSource: .init(identifier: source), target: .init(identifier: target), preferredStrategy: .lowLatency)
            defer { session.cancel() }
            XCTAssertFalse(session.canRequestDownloads)
            let response = try await session.translate(text)
            XCTAssertFalse(response.targetText.isEmpty)
            XCTAssertNotEqual(response.targetText, text)
        }
#endif
    }
}
