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

enum OfflineEvent: Sendable {
    case transcript(id: UUID, text: String, isFinal: Bool)
    case translation(id: UUID, text: String)
    case failure(String)
}

@MainActor
protocol OfflineTranslating: AnyObject {
    var onEvent: (@MainActor @Sendable (OfflineEvent) -> Void)? { get set }
    func start(source: String, target: String) async throws
    func appendAudio(_ data: Data)
    func finish() async throws
    func cancel()
}
