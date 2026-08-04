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

    /// Interruption lifecycle reported to the coordinator. `began`: the system
    /// paused capture (call, Siri…). `resumed`: the engine restarted
    /// successfully. `resumeFailed`: the restart attempt threw.
    enum InterruptionEvent: Sendable {
        case began
        case resumed
        case resumeFailed(String)
    }

    enum InterruptionDecision: Equatable, Sendable {
        case pause
        case restart
        case fail(String)
        case ignore
    }

    /// Converts the untyped AVAudioSession notification payload into a small,
    /// deterministic state-machine input that can be unit tested without audio
    /// hardware or a running AVAudioSession.
    static func interruptionDecision(typeRaw: UInt?, optionsRaw: UInt?) -> InterruptionDecision {
        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return .ignore }
        switch type {
        case .began:
            return .pause
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            return options.contains(.shouldResume)
                ? .restart
                : .fail("System declined audio resume")
        @unknown default:
            return .ignore
        }
    }

    private let engine = AVAudioEngine()
    private let converterQueue = DispatchQueue(label: "BabelTable.AudioConverter", qos: .userInitiated)
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    /// Mode of the last `start(mode:)` — reused by `restart()`.
    private var activeMode: CaptureMode = .voiceChat
    private var observersInstalled = false

    /// Smallest interval between `onLevel` callbacks (~10 Hz).
    private static let levelInterval: TimeInterval = 0.1
    private var lastLevelSentAt: Date = .distantPast

    /// Set by caller. Receives PCM16 24kHz mono little-endian audio data.
    var onChunk: (@Sendable (Data) -> Void)?

    /// Mic loudness 0…1 at ~10 Hz while capturing; drives the level meter.
    var onLevel: (@Sendable (Float) -> Void)?

    /// System audio interruptions (phone call, Siri, …).
    var onInterruption: (@Sendable (InterruptionEvent) -> Void)?

    /// Media services were reset — the whole audio stack must be rebuilt.
    var onMediaServicesReset: (@Sendable () -> Void)?

    /// Requests record permission. Returns true if granted.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    nonisolated func start(mode: CaptureMode = .voiceChat) async throws {
        activeMode = mode
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
        installObservers()
    }

    /// Full stop + start using the mode of the last `start(mode:)` call.
    /// Used to recover from interruptions, media-services resets, and
    /// returning from the background.
    nonisolated func restart() async throws {
        stop()
        try await start(mode: activeMode)
    }

    nonisolated func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        converter = nil
        targetFormat = nil
    }

    nonisolated private func handle(buffer: AVAudioPCMBuffer) {
        emitLevel(for: buffer)
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

    // MARK: - Level metering

    /// RMS of the source buffer, mapped from -50 dB … -12 dB to 0…1 — the
    /// practical speech range for a mic lying on a table. Throttled to ~10 Hz.
    nonisolated private func emitLevel(for buffer: AVAudioPCMBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelSentAt) >= Self.levelInterval,
              let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        lastLevelSentAt = now

        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frames { sum += samples[i] * samples[i] }
        let rms = sqrt(sum / Float(frames))
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = min(max((db + 50) / 38, 0), 1)
        onLevel?(normalized)
    }

    // MARK: - System audio events

    nonisolated private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            self?.handleInterruption(note)
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.handleRouteChange()
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            diagLog(.warn, tag: "Audio", "Media services reset")
            self.onMediaServicesReset?()
        }
    }

    nonisolated private func handleInterruption(_ note: Notification) {
        let decision = Self.interruptionDecision(
            typeRaw: note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            optionsRaw: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
        )
        switch decision {
        case .pause:
            diagLog(.warn, tag: "Audio", "Interruption began (call/Siri)")
            engine.stop()
            onInterruption?(.began)
        case .restart:
            Task {
                do {
                    try await self.restart()
                    self.onInterruption?(.resumed)
                } catch {
                    self.onInterruption?(.resumeFailed(error.localizedDescription))
                }
            }
        case .fail(let message):
            diagLog(.warn, tag: "Audio", "Interruption ended, resume declined")
            onInterruption?(.resumeFailed(message))
        case .ignore:
            return
        }
    }

    /// Route changes (headset (un)plugged, …) can change the input hardware
    /// format; rebuild the converter against the new format, otherwise
    /// conversion errors are silently swallowed and audio goes quiet.
    nonisolated private func handleRouteChange() {
        guard engine.isRunning, let targetFormat else { return }
        let nativeFormat = engine.inputNode.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0,
              let newConverter = AVAudioConverter(from: nativeFormat, to: targetFormat) else { return }
        converter = newConverter
        diagLog(.info, tag: "Audio", "Route changed; converter rebuilt (\(Int(nativeFormat.sampleRate)) Hz)")
    }
}
