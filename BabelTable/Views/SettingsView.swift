import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(UsageTracker.self) private var usage

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Label("On-device translation", systemImage: "iphone.gen3.radiowaves.left.and.right")
                Text("No account, API key, or translation subscription is required. Prepare language models before going offline.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Languages") {
                Picker("Your language", selection: $settings.primaryLanguageCode) {
                    ForEach(SupportedLanguages.outputs) { Text($0.labeled).tag($0.code) }
                }
                Picker("Other person's language", selection: $settings.secondaryLanguageCode) {
                    ForEach(SupportedLanguages.outputs) { Text($0.labeled).tag($0.code) }
                }
                if coordinator.isSessionActive { Text("Stop the conversation before changing languages.").font(.caption) }
            }
            .disabled(coordinator.isSessionActive)
            Section {
                OfflineModelsView(pair: SessionLanguagePair(primary: settings.primaryLanguageCode, secondary: settings.secondaryLanguageCode))
                    .id("\(settings.primaryLanguageCode)-\(settings.secondaryLanguageCode)")
            }
            Section("Display") {
                Picker("Layout", selection: $settings.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Label utterances by", selection: $settings.speakerLabelStyle) {
                    ForEach(SpeakerLabelStyle.allCases) { Text($0.displayName).tag($0) }
                }
                if settings.speakerLabelStyle == .speaker {
                    TextField("Your name", text: $settings.primarySpeakerName)
                    TextField("Other person's name", text: $settings.secondarySpeakerName)
                }
            }
            Section("Microphone") {
                Picker("Balance speaker volume", selection: $settings.autoLevel) {
                    ForEach(AutoLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Choose the speaking language before each person talks. Speak one at a time. Audio spoken while paused is not captured.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Usage") {
                LabeledContent("Today", value: String(format: "%.1f min", usage.todayMinutes))
                LabeledContent("All time", value: String(format: "%.1f min", usage.totalMinutes))
                Text("Conversation duration is stored only on this device. There are no per-minute translation charges.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("Microphone audio is processed in memory and is not saved. Transcripts are saved locally in History. You control sharing and deletion. Apple manages model downloads and may collect framework usage diagnostics.")
                Link("Privacy Policy", destination: URL(string: "https://github.com/everettjf/babeltable/blob/main/PRIVACY.md")!)
            }
            Section("About") {
                LabeledContent("Requires", value: "iOS 27")
                NavigationLink("Diagnostics") { DiagnosticsView() }
                NavigationLink("How to use BabelTable") { OnboardingView() }
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(BabelTheme.pageBackground)
    }
}
