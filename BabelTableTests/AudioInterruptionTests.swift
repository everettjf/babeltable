import AVFoundation
import XCTest
@testable import BabelTable

final class AudioInterruptionTests: XCTestCase {
    func testInterruptionBeganPausesCapture() {
        XCTAssertEqual(
            AudioCaptureService.interruptionDecision(
                typeRaw: AVAudioSession.InterruptionType.began.rawValue,
                optionsRaw: nil
            ),
            .pause
        )
    }

    func testInterruptionEndsWithResumeRestartsCapture() {
        XCTAssertEqual(
            AudioCaptureService.interruptionDecision(
                typeRaw: AVAudioSession.InterruptionType.ended.rawValue,
                optionsRaw: AVAudioSession.InterruptionOptions.shouldResume.rawValue
            ),
            .restart
        )
    }

    func testInterruptionWithoutResumeBecomesVisibleFailure() {
        XCTAssertEqual(
            AudioCaptureService.interruptionDecision(
                typeRaw: AVAudioSession.InterruptionType.ended.rawValue,
                optionsRaw: 0
            ),
            .fail("System declined audio resume")
        )
    }

    func testMalformedNotificationIsIgnored() {
        XCTAssertEqual(
            AudioCaptureService.interruptionDecision(typeRaw: nil, optionsRaw: nil),
            .ignore
        )
    }
}
