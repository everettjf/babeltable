import SwiftUI

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 52)).foregroundStyle(BabelTheme.primary)
                    Text("Two languages. One table.").font(.largeTitle.bold())
                    Text("Private conversations, translated on your iPhone.").font(.title3)
                    Label("Prepare your languages", systemImage: "arrow.down.circle")
                        .font(.headline)
                    Text("Choose two languages in Settings and download their speech and translation models. This first setup requires an internet connection and available storage.")
                    Label("Speak one at a time", systemImage: "mic.fill").font(.headline)
                    Text("Start a conversation, choose the speaking language, and talk. Read the original words as they appear; the translation follows each completed phrase. Switch the speaking language for the other person.")
                    Label("Keep it offline", systemImage: "wifi.slash").font(.headline)
                    Text("After setup, supported languages work in airplane mode. No account or API key is needed. Audio stays on your device and is never saved; conversations are stored in History.")
                    Button("Get started") {
                        settings.hasCompletedOnboarding = true
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .padding(28).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .background(BabelTheme.pageBackground)
        }
    }
}
