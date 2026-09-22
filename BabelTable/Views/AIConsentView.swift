import SwiftUI

/// Consent gates both realtime audio and optional text refinement.
struct AIConsentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    var onConsent: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Translate with OpenAI")
                        .font(.title.bold())
                    Text("When you start, microphone audio is sent directly to OpenAI to recognize speech and translate it. Both people should agree before you record the conversation.")
                    Text("If you enable refinement in Advanced settings, the original text, draft translation, up to three earlier turns, and your glossary are also sent to OpenAI in a separate paid request.")
                    Text("Your API key is used to authenticate these requests. BabelTable has no developer-operated server. Conversation history is saved on your device; iOS device backups may include it. You can delete history at any time.")
                    Link("BabelTable Privacy Policy", destination: URL(string: "https://github.com/everettjf/babeltable/blob/main/PRIVACY.md")!)
                    Link("OpenAI Privacy Policy", destination: URL(string: "https://openai.com/policies/privacy-policy/")!)
                    if settings.hasAIConsent {
                        Text("You have allowed this data sharing. Withdrawing permission stops the current session and prevents new translation requests until you agree again.")
                        Button("Withdraw permission", role: .destructive) {
                            coordinator.stop()
                            settings.aiConsentVersion = 0
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Agree and continue") {
                            settings.aiConsentVersion = AppSettings.currentConsentVersion
                            dismiss()
                            onConsent()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("consent.agree")
                        Button("Not now") { dismiss() }
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
