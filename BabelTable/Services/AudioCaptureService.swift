import AVFoundation
import Foundation

/// Captures microphone audio and emits PCM16 24kHz mono `Data` chunks
/// suitable for `gpt-realtime-translate` `session.input_audio_buffer.append`.
///
/// The `onChunk` closure fires on a background audio thread; the consumer is
/// responsible for hopping to MainActor or another isolation domain as needed.
nonisolated final class AudioCaptureService: @unchecked Sendable {
    enum AudioError: Error, LocalizedError {
        case permissionDenied
        case engineUnavailable
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Microphone permission denied."
            case .engineUnavailable: return "Audio engine is unavailable."
            case .converterUnavailable: return "Could not initialize audio converter."
            }
        }
    }

    /// Target sample rate required by the OpenAI Realtime API.
    static let targetSampleRate: Double = 24_000

    /// Audio session capture mode. `.measurement` keeps raw audio (no AGC),
    /// `.voiceChat` enables system AGC + echo cancellation which evens out
    /// volume between near and far speakers.
    enum CaptureMode: Sendable {
        case measurement
        case voiceChat

        var sessionMode: AVAudioSession.Mode {
            switch self {
            case .measurement: return .measurement
            case .voiceChat: return .voiceChat
            }
        }
    }

    private let engine = AVAudioEngine()
    private let converterQueue = DispatchQueue(label: "BabelTable.AudioConverter", qos: .userInitiated)
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    /// Set by caller. Receives PCM16 24kHz mono little-endian audio data.
    var onChunk: (@Sendable (Data) -> Void)?

    /// Requests record permission. Returns true if granted.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    nonisolated func start(mode: CaptureMode = .voiceChat) async throws {
        let granted = await Self.requestPermission()
        guard granted else { throw AudioError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        // .voiceChat is .playAndRecord-only; pair the category accordingly so the
        // selected mode actually takes effect.
        let category: AVAudioSession.Category = (mode == .voiceChat) ? .playAndRecord : .record
        try session.setCategory(category, mode: mode.sessionMode, options: [.allowBluetoothHFP])
        try session.setPreferredSampleRate(Self.targetSampleRate)
        try session.setActive(true, options: [])

        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)

        guard nativeFormat.sampleRate > 0 else {
            throw AudioError.engineUnavailable
        }

        let pcm16Format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: true
        )
        guard let pcm16Format,
              let converter = AVAudioConverter(from: nativeFormat, to: pcm16Format) else {
            throw AudioError.converterUnavailable
        }
        self.converter = converter
        self.targetFormat = pcm16Format

        // Tap with a buffer size around 100ms of native audio.
        let tapBufferSize = AVAudioFrameCount(nativeFormat.sampleRate * 0.1)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.handle(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
    }

    nonisolated func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        converter = nil
        targetFormat = nil
    }

    nonisolated private func handle(buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }

        // Compute output capacity for the target format.
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            return
        }

        // Reference-typed flag so the @Sendable input block can mutate it
        // under Swift 6 strict concurrency. The converter calls this
        // synchronously, so no actual concurrent access occurs.
        final class Flag: @unchecked Sendable { var consumed = false }
        let flag = Flag()
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if flag.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            flag.consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        var nsError: NSError?
        let status = converter.convert(to: outBuffer, error: &nsError, withInputFrom: inputBlock)

        guard status != .error, status != .endOfStream else { return }
        guard outBuffer.frameLength > 0,
              let int16ChannelData = outBuffer.int16ChannelData else { return }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: int16ChannelData[0], count: byteCount)
        onChunk?(data)
    }
}
