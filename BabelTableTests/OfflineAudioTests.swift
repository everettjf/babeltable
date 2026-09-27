import AVFoundation
import Speech
import XCTest
@testable import BabelTable

@MainActor
final class OfflineAudioTests: XCTestCase {
    func testIOS27ConverterPreservesDurationAcrossChunkBoundaries() throws {
        let captureFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000,
                                                       channels: 1, interleaved: true))
        let modelFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                                     channels: 1, interleaved: true))
        let converter = AnalyzerInputConverter(analyzerFormat: modelFormat)
        var inputs: [AnalyzerInput] = []
        for _ in 0..<10 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: 2400))
            buffer.frameLength = 2400
            let samples = try XCTUnwrap(buffer.int16ChannelData)
            samples[0].initialize(repeating: 0, count: 2400)
            inputs += try converter.convert(buffer, at: nil)
        }
        inputs += try converter.flush()
        XCTAssertFalse(inputs.isEmpty)
        XCTAssertTrue(inputs.allSatisfy { $0.bufferFormat.sampleRate == 16_000 })
        XCTAssertEqual(inputs.reduce(0) { $0 + $1.bufferDuration.seconds }, 1, accuracy: 0.005)
    }
}
