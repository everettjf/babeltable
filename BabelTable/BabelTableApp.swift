import SwiftUI

@main
struct BabelTableApp: App {
    @State private var settings = AppSettings()
    @State private var store = SessionStore()
    @State private var usage = UsageTracker()
    @State private var coordinator: TranslationCoordinator

    init() {
        let s = AppSettings()
        let store = SessionStore()
        let usage = UsageTracker()
        _settings = State(initialValue: s)
        _store = State(initialValue: store)
        _usage = State(initialValue: usage)
        _coordinator = State(initialValue: TranslationCoordinator(
            settings: s,
            store: store,
            usage: usage
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(store)
                .environment(usage)
                .environment(coordinator)
                .fullScreenCover(isPresented: needsOnboarding) {
                    OnboardingView()
                        .environment(settings)
                }
        }
    }

    /// Re-show onboarding on launch when either:
    ///   - the user has never finished it, or
    ///   - they have no API key stored (e.g. cleared it from Settings, or
    ///     installed onto a new device where the Keychain item is missing).
    private var needsOnboarding: Binding<Bool> {
        Binding(
            get: { !settings.hasCompletedOnboarding || !settings.hasAPIKey },
            set: { newValue in
                if !newValue { settings.hasCompletedOnboarding = true }
            }
        )
    }
}
