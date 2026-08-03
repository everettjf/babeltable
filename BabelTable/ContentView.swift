import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Translate", systemImage: "waveform")
                }

            ArchiveView()
                .tabItem {
                    Label("Archive", systemImage: "tray.full")
                }
        }
    }
}

#Preview {
    let settings = AppSettings()
    let store = SessionStore()
    let usage = UsageTracker()
    return ContentView()
        .environment(settings)
        .environment(store)
        .environment(usage)
        .environment(TranslationCoordinator(settings: settings, store: store, usage: usage))
}
