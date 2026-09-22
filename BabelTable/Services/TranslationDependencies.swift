import Foundation

@MainActor
protocol AudioCapturing: AnyObject {
    var onChunk: (@MainActor @Sendable (Data) -> Void)? { get set }
    var onLevel: (@MainActor @Sendable (Float) -> Void)? { get set }
    var onInterruption: (@MainActor @Sendable (AudioCaptureService.InterruptionEvent) -> Void)? { get set }
    var onMediaServicesReset: (@MainActor @Sendable () -> Void)? { get set }
    func start(mode: AudioCaptureService.CaptureMode) async throws
    func restart() async throws
    func stop()
}

nonisolated protocol RealtimeConnection: AnyObject, Sendable {
    func connect()
    func close()
    func appendAudio(_ data: Data)
}

extension RealtimeTranslator: RealtimeConnection {}
