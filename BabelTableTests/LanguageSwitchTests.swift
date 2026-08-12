import XCTest
@testable import BabelTable

@MainActor final class LanguageSwitchTests: XCTestCase {
    func testLiveSessionKeepsCapturedLanguagePair() {
        var configuredPrimary = "en"
        var configuredSecondary = "zh"
        let runningSession = SessionLanguagePair(
            primary: configuredPrimary,
            secondary: configuredSecondary
        )

        configuredPrimary = "fr"
        configuredSecondary = "de"

        XCTAssertEqual(runningSession, SessionLanguagePair(primary: "en", secondary: "zh"))
        XCTAssertEqual(
            SessionLanguagePair(primary: configuredPrimary, secondary: configuredSecondary),
            SessionLanguagePair(primary: "fr", secondary: "de")
        )
    }

    func testRegionalCodesAreNormalizedForNewSession() {
        XCTAssertEqual(
            SessionLanguagePair(primary: "zh-Hant", secondary: "pt-BR"),
            SessionLanguagePair(primary: "zh", secondary: "pt")
        )
    }

    func testUnsupportedCodesUseSafeDefaults() {
        XCTAssertEqual(
            SessionLanguagePair(primary: "xx", secondary: "yy"),
            SessionLanguagePair(primary: "en", secondary: "zh")
        )
    }
}
