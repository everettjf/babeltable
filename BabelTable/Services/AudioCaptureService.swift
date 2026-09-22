import AVFoundation
import Foundation

/// Captures microphone audio and emits PCM16 24kHz mono `Data` chunks
/// suitable for `gpt-realtime-translate` `session.input_audio_buffer.append`.
///
/// Conversion runs on the audio tap; lifecycle and delivery are serialized on
/// MainActor so a stopped capture cannot restart or deliver stale audio.
@MainActor
final class AudioCaptureService: AudioCapturing {
    nonisolated enum AudioError: Error, LocalizedError {
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
    nonisolated enum CaptureMode: Sendable {
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
    nonisolated enum InterruptionEvent: Sendable {
        case began
        case resumed
        case resumeFailed(String)
    }

    nonisolated enum InterruptionDecision: Equatable, Sendable {
        case pause
        case restart
        case fail(String)
        case ignore
    }

    /// Converts the untyped AVAudioSession notification payload into a small,
    /// deterministic state-machine input that can be unit tested without audio
    /// hardware or a running AVAudioSession.
    nonisolated static func interruptionDecision(typeRaw: UInt?, optionsRaw: UInt?) -> InterruptionDecision {
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

    private var engine = AVAudioEngine()
    private var generation = UUID()
    private var wantsCapture = false
    private var observers: [NSObjectProtocol] = []

    /// Mode of the last `start(mode:)` — reused by `restart()`.
    private var activeMode: CaptureMode = .voiceChat

    /// Set by caller. Receives PCM16 24kHz mono little-endian audio data.
    var onChunk: (@MainActor @Sendable (Data) -> Void)?

    /// Mic loudness 0…1 at ~10 Hz while capturing; drives the level meter.
    var onLevel: (@MainActor @Sendable (Float) -> Void)?

    /// System audio interruptions (phone call, Siri, …).
    var onInterruption: (@MainActor @Sendable (InterruptionEvent) -> Void)?

    /// Media services were reset — the whole audio stack must be rebuilt.
    var onMediaServicesReset: (@MainActor @Sendable () -> Void)?

    /// Requests record permission. Returns true if granted.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func start(mode: CaptureMode = .voiceChat) async throws {
        activeMode = mode
        wantsCapture = true
        let requestGeneration = generation
        let granted = await Self.requestPermission()
        guard requestGeneration == generation, wantsCapture, !Task.isCancelled else { throw CancellationError() }
        guard granted else { wantsCapture = false; throw AudioError.permissionDenied }

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
        let converterState = BufferConverter(converter: converter, targetFormat: pcm16Format)

        // Tap with a buffer size around 100ms of native audio.
        let tapBufferSize = AVAudioFrameCount(nativeFormat.sampleRate * 0.1)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: nativeFormat) { [weak self] buffer, _ in
            guard let chunk = converterState.convert(buffer) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == requestGeneration, self.wantsCapture else { return }
                self.onLevel?(chunk.level)
                self.onChunk?(chunk.data)
            }
        }

        engine.prepare()
        try engine.start()
        installObservers()
    }

    /// Full stop + start using the mode of the last `start(mode:)` call.
    /// Used to recover from interruptions, media-services resets, and
    /// returning from the background.
    func restart() async throws {
        stop()
        try await start(mode: activeMode)
    }

    func stop() {
        generation = UUID()
        wantsCapture = false
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

    }

    // MARK: - System audio events

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let decision = Self.interruptionDecision(
                typeRaw: note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                optionsRaw: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
            Task { @MainActor [weak self] in self?.handleInterruption(decision) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard let raw, let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in self?.recoverCapture() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wantsCapture else { return }
                self.stop()
                self.engine = AVAudioEngine()
                self.onMediaServicesReset?()
            }
        })
    }

    private func handleInterruption(_ decision: InterruptionDecision) {
        guard wantsCapture else { return }
        switch decision {
        case .pause:
            engine.pause()
            onInterruption?(.began)
        case .restart:
            recoverCapture()
        case .fail(let message):
            onInterruption?(.resumeFailed(message))
        case .ignore: break
        }
    }

    private func recoverCapture() {
        guard wantsCapture else { return }
        onInterruption?(.began)
        stop()
        let requestGeneration = generation
        Task { @MainActor [weak self] in
            guard let self, self.generation == requestGeneration else { return }
            do {
                try await self.start(mode: self.activeMode)
                guard self.generation == requestGeneration, self.wantsCapture else { return }
                self.onInterruption?(.resumed)
            } catch {
                guard self.generation == requestGeneration else { return }
                self.onInterruption?(.resumeFailed("Audio capture could not resume"))
            }
        }
    }
}

/// Owned by one engine tap. The converter never races with engine lifecycle
/// changes; a replacement tap receives a new converter instance.
nonisolated private final class BufferConverter: @unchecked Sendable {
    let converter: AVAudioConverter
    let targetFormat: AVAudioFormat

    init(converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        self.converter = converter
        self.targetFormat = targetFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> (data: Data, level: Float)? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        final class Flag: @unchecked Sendable { var consumed = false }
        let flag = Flag()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if flag.consumed { state.pointee = .noDataNow; return nil }
            flag.consumed = true
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData else { return nil }
        var sum: Float = 0
        for i in 0..<Int(output.frameLength) {
            let sample = Float(samples[0][i]) / 32768
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(output.frameLength))
        let level = min(max((20 * log10(max(rms, 1e-6)) + 50) / 38, 0), 1)
        return (Data(bytes: samples[0], count: Int(output.frameLength) * 2), level)
    }
}
