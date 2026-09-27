import SwiftUI

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(BabelTheme.primary)
                    Text("Two languages. One table.")
                        .font(.largeTitle.bold())

                    welcomeStep("Download once", systemImage: "arrow.down.circle",
                                detail: "Choose two languages in Settings and download their models while online.")
                    welcomeStep("Take turns", systemImage: "mic.fill",
                                detail: "Select who is speaking. Read the translation, then switch.")
                    welcomeStep("Talk offline", systemImage: "wifi.slash",
                                detail: "After setup, translation stays on your device. No account needed.")
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    settings.hasCompletedOnboarding = true
                    dismiss()
                } label: {
                    Text("Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.getStarted")
                .frame(maxWidth: 572)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
            .background(BabelTheme.pageBackground)
        }
    }

    private func welcomeStep(_ title: LocalizedStringKey, systemImage: String,
                             detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
