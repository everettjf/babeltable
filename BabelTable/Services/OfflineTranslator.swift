import AVFoundation
import Foundation
import Speech
import Translation

/// One selected speaker at a time. All recognition and translation uses installed assets.
/// iOS 27's converter handles model-specific audio formats without a cloud fallback.
@MainActor
final class OfflineTranslator: OfflineTranslating {
    var onEvent: (@MainActor @Sendable (OfflineEvent) -> Void)?
    private var analyzer: SpeechAnalyzer?
    private var converter: AnalyzerInputConverter?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Error>?
    private var translation: TranslationSession?
    private var generation = UUID()
    private var ids: [Double: UUID] = [:]

    func start(source: String, target: String) async throws {
        cancel()
        let token = generation
        let pair = SessionLanguagePair(primary: source, secondary: target)
        switch await OfflineModels.status(for: pair) {
        case .unsupported: throw OfflineError.unsupported
        case .needsDownload: throw OfflineError.modelsMissing
        case .ready: break
        }
        guard token == generation else { throw CancellationError() }
        // Assets may have been installed by another app; reserve the existing locales for this app.
        try await OfflineModels.reserveSpeech(for: pair)
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        guard let locale = await OfflineModels.locale(for: source) else { throw OfflineError.unsupported }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              format.commonFormat == .pcmFormatInt16, format.channelCount == 1 else {
            throw OfflineError.audioFormat
        }
        guard token == generation else { throw CancellationError() }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        converter = AnalyzerInputConverter(analyzerFormat: format)
        let session = TranslationSession(installedSource: .init(identifier: source), target: .init(identifier: target),
                                         preferredStrategy: .lowLatency)
        translation = session
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(100))
        self.continuation = continuation
        resultsTask = Task { @MainActor [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    let key = result.range.start.seconds
                    let id = self.ids[key] ?? UUID()
                    self.ids[key] = id
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    self.onEvent?(.transcript(id: id, text: text, isFinal: result.isFinal))
                    if result.isFinal {
                        let response = try await session.translate(text)
                        guard self.generation == token, !Task.isCancelled else { return }
                        self.onEvent?(.translation(id: id, text: response.targetText))
                    }
                }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.onEvent?(.failure("Local speech recognition or translation failed. Check downloaded models in Settings, then try again."))
                throw error
            }
        }
        try await analyzer.prepareToAnalyze(in: format)
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        try await analyzer.start(inputSequence: stream)
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
    }

    func appendAudio(_ data: Data) {
        guard !data.isEmpty, data.count.isMultiple(of: 2), let converter, let continuation,
              let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: AudioCaptureService.targetSampleRate,
                                         channels: 1, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 2)),
              let samples = buffer.int16ChannelData else { return }
        buffer.frameLength = buffer.frameCapacity
        data.copyBytes(to: UnsafeMutableRawBufferPointer(start: samples[0], count: data.count))
        do {
            for input in try converter.convert(buffer, at: nil) {
                if case .dropped = continuation.yield(input) { throw OfflineError.overloaded }
            }
        } catch {
            onEvent?(.failure(error.localizedDescription))
        }
    }

    /// Drain the final audio and await its translation before saving or switching speaker.
    func finish() async throws {
        if let converter, let continuation {
            for input in try converter.flush() {
                if case .dropped = continuation.yield(input) { throw OfflineError.overloaded }
            }
        }
        continuation?.finish()
        continuation = nil
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        try await resultsTask?.value
        cancel()
    }

    func cancel() {
        generation = UUID()
        continuation?.finish()
        continuation = nil
        resultsTask?.cancel()
        resultsTask = nil
        translation?.cancel()
        translation = nil
        let old = analyzer
        analyzer = nil
        if let old { Task { await old.cancelAndFinishNow() } }
        converter = nil
        ids = [:]
    }
}
