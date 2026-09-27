import SwiftUI
import XCTest
@testable import BabelTable

/// Real application views with synthetic conversation data, never user recordings.
@MainActor
final class MarketingScreenshotTests: XCTestCase {
    func testCaptureStoreScreenshots() async throws {
        let suite = "Marketing-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let settings = AppSettings(defaults: defaults)
        let store = SessionStore(folderURL: folder)
        let usage = UsageTracker(fileURL: folder.appendingPathComponent("usage.data"))
        let engine = MarketingTranslator()
        let coordinator = TranslationCoordinator(settings: settings, store: store, usage: usage,
            audio: MarketingAudio(), translatorFactory: { engine })
        defer {
            coordinator.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        await coordinator.start()
        let first = UUID()
        engine.onEvent?(.transcript(id: first, text: "Hello! Is there a good café nearby?", isFinal: true))
        engine.onEvent?(.translation(id: first, text: "你好！附近有不错的咖啡馆吗？"))
        coordinator.selectSpeaker(primary: false)
        for _ in 0..<40 { await Task.yield() }
        let second = UUID()
        engine.onEvent?(.transcript(id: second, text: "有，就在街角。我们一起去吧。", isFinal: true))
        engine.onEvent?(.translation(id: second, text: "Yes, just around the corner. Let's go together."))
        XCTAssertEqual(coordinator.chatTurns.count, 2)
        let date = Date(timeIntervalSince1970: 1_790_503_740)
        let archive = ChatSession(startedAt: date, endedAt: date.addingTimeInterval(84),
            primaryLanguageCode: "en", secondaryLanguageCode: "zh", primaryLines: [], secondaryLines: [],
            chatTurns: coordinator.chatTurns)
        XCTAssertTrue(store.save(archive))
        for (device, size) in [("iphone", CGSize(width: 393, height: 852)), ("ipad", CGSize(width: 1024, height: 1366))] {
            for page in ["face", "chat", "history", "detail", "welcome"] {
                settings.displayMode = page == "face" ? .faceToFace : .chat
                let screen: AnyView
                switch page {
                case "history": screen = AnyView(ArchiveView())
                case "detail": screen = AnyView(NavigationStack { SessionDetailView(session: archive) })
                case "welcome": screen = AnyView(OnboardingView())
                default: screen = AnyView(HomeView())
                }
                let content = screen.environment(settings).environment(store).environment(usage).environment(coordinator)
                    .environment(\.colorScheme, .dark).environment(\.locale, Locale(identifier: "en_US"))
                    .environment(\.horizontalSizeClass, device == "ipad" ? .regular : .compact)
                let controller = UIHostingController(rootView: content)
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: size)
                window.overrideUserInterfaceStyle = .dark
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(400))
                let format = UIGraphicsImageRendererFormat()
                format.scale = device == "ipad" ? 2 : 3
                format.opaque = true
                let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "store-\(device)-\(page)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }
}

@MainActor
private final class MarketingTranslator: OfflineTranslating {
    var onEvent: (@MainActor @Sendable (OfflineEvent) -> Void)?
    func start(source: String, target: String) async throws {}
    func appendAudio(_ data: Data) {}
    func finish() async throws {}
    func cancel() {}
}

@MainActor
private final class MarketingAudio: AudioCapturing {
    var onChunk: (@MainActor @Sendable (Data) -> Void)?
    var onLevel: (@MainActor @Sendable (Float) -> Void)?
    var onInterruption: (@MainActor @Sendable (AudioCaptureService.InterruptionEvent) -> Void)?
    var onMediaServicesReset: (@MainActor @Sendable () -> Void)?
    func start(mode: AudioCaptureService.CaptureMode) async throws {}
    func restart() async throws {}
    func stop() {}
}
