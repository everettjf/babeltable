import SwiftUI
import XCTest
@testable import BabelTable

/// Render real UIKit-hosted SwiftUI screens into reviewable test attachments.
/// These snapshots supplement (not replace) physical VoiceOver/interaction checks.
@MainActor
final class ReleaseLayoutTests: XCTestCase {
    func testReleaseLayouts() async throws {
        let name = "BabelTable-Layout-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        let keychain = KeychainStore(service: name)
        let settings = AppSettings(defaults: defaults, keychain: keychain)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let store = SessionStore(folderURL: folder)
        let usage = UsageTracker(fileURL: folder.appendingPathComponent("usage.data"))
        let coordinator = TranslationCoordinator(settings: settings, store: store, usage: usage, monitorConnectivity: false)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: folder)
        }
        let screens: [(String, AnyView)] = [
            ("home", AnyView(HomeView())),
            ("onboarding", AnyView(OnboardingView())),
            ("settings", AnyView(NavigationStack { SettingsView() })),
            ("consent", AnyView(AIConsentView()))
        ]
        for (device, size, typeSize) in [
            ("iPhone", CGSize(width: 393, height: 852), DynamicTypeSize.large),
            ("iPhone-large-text", CGSize(width: 393, height: 852), DynamicTypeSize.accessibility3),
            ("iPad", CGSize(width: 1024, height: 1366), DynamicTypeSize.large)
        ] {
            for (name, screen) in screens {
                let content = screen.environment(settings).environment(store).environment(usage)
                    .environment(coordinator).environment(\.dynamicTypeSize, typeSize)
                    .environment(\.horizontalSizeClass, size.width >= 600 ? .regular : .compact)
                let controller = UIHostingController(rootView: content)
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(device)-\(name)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }
}
