import AVFoundation
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
        XCTAssertEqual(status, .ready, "This device integration suite requires prepared English/Chinese models.")
        guard status == .ready else { return }
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

    func testInstalledModelsSupportColdSpeechStartAndRestart() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Apple speech assets require a physical device.")
#else
        let pair = SessionLanguagePair(primary: "en", secondary: "zh")
        let status = await OfflineModels.status(for: pair)
        XCTAssertEqual(status, .ready, "Prepared models must remain usable on a fresh launch.")
        guard status == .ready else { return }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "english", withExtension: "wav"))
        // A fresh instance matches the first Start after opening the app. Repeat to check teardown.
        for _ in 0..<2 {
            let translator = OfflineTranslator()
            defer { translator.cancel() }
            var originals: [String] = []
            var translations: [String] = []
            translator.onEvent = { event in
                switch event {
                case .transcript(_, let text, let final): if final { originals.append(text) }
                case .translation(_, let text): translations.append(text)
                case .failure(let message): XCTFail(message)
                }
            }
            try await translator.start(source: "en", target: "zh")
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
            XCTAssertGreaterThan(file.length, 0, "The synthetic speech fixture must contain audio.")
            XCTAssertEqual(file.processingFormat.sampleRate, AudioCaptureService.targetSampleRate)
            while file.framePosition < file.length {
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2400))
                try file.read(into: buffer)
                let samples = try XCTUnwrap(buffer.int16ChannelData)
                translator.appendAudio(Data(bytes: samples[0], count: Int(buffer.frameLength) * 2))
                try await Task.sleep(for: .milliseconds(50))
            }
            try await translator.finish()
            XCTAssertTrue(originals.joined(separator: " ").lowercased().contains("thank"))
            XCTAssertFalse(translations.joined().isEmpty)
        }
#endif
    }

}
