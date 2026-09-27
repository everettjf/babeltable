import AVFoundation
import XCTest
@testable import BabelTable

final class AudioInterruptionTests: XCTestCase {
    func testOnlySystemDeactivationPausesConversation() {
        XCTAssertTrue(AudioCaptureService.shouldPause(for: .system))
        XCTAssertFalse(AudioCaptureService.shouldPause(for: .app))
    }
}
