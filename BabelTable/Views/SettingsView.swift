import Charts
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UsageTracker.self) private var usage

    @State private var apiKeyDraft: String = ""
    @State private var apiKeyVisible: Bool = false
    @State private var saved = false
    @State private var showOnboarding = false
    @State private var confirmResetUsage = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                if apiKeyVisible {
                    TextField("sk-…", text: $apiKeyDraft, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                } else {
                    SecureField("sk-…", text: $apiKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                HStack {
                    Toggle("Show key", isOn: $apiKeyVisible)
                    Spacer()
                    Button(saved ? "Saved" : "Save") {
                        settings.apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            saved = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                    Label("Open OpenAI API keys dashboard", systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text("Stored securely in the iOS Keychain on this device.")
            }

            Section {
                Picker("Primary (your language)", selection: $settings.primaryLanguageCode) {
                    ForEach(SupportedLanguages.outputs) { lang in
                        Text("\(lang.nativeName) · \(lang.name)").tag(lang.code)
                    }
                }
                Picker("Secondary (the other person)", selection: $settings.secondaryLanguageCode) {
                    ForEach(SupportedLanguages.outputs) { lang in
                        Text("\(lang.nativeName) · \(lang.name)").tag(lang.code)
                    }
                }
            } header: {
                Text("Languages")
            } footer: {
                Text("Two simultaneous translation sessions run — one for each language. The model auto-detects who is speaking which.")
            }

            labelsSection

            refinementSection

            audioRecognitionSection

            usageSection

            Section {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Connection events and detailed error messages from the translation service. Helpful when a session unexpectedly stops.")
            }

            Section {
                Button {
                    showOnboarding = true
                } label: {
                    Label("Show welcome tour again", systemImage: "sparkles")
                }
            } header: {
                Text("Help")
            }

            Section {
                LabeledContent("Model", value: "gpt-realtime-translate")
                LabeledContent("Sample rate", value: "24 kHz PCM16")
                LabeledContent("List price", value: priceString(UsageTracker.pricePerMinute) + " / min")
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .onAppear { apiKeyDraft = settings.apiKey }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .confirmationDialog("Reset usage history?",
                            isPresented: $confirmResetUsage,
                            titleVisibility: .visible) {
            Button("Reset", role: .destructive) { usage.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the daily minute totals shown above. Archived chats are not affected.")
        }
    }

    // MARK: - Labels

    @ViewBuilder
    private var labelsSection: some View {
        @Bindable var settings = settings

        Section {
            Picker("Label utterances by", selection: $settings.speakerLabelStyle) {
                ForEach(SpeakerLabelStyle.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }

            if settings.speakerLabelStyle == .speaker {
                TextField("Your name", text: $settings.primarySpeakerName)
                    .textInputAutocapitalization(.words)
                TextField("Other person's name", text: $settings.secondarySpeakerName)
                    .textInputAutocapitalization(.words)
            }
        } header: {
            Text("Transcript labels")
        } footer: {
            Text(settings.speakerLabelStyle == .speaker
                 ? "Each utterance is tagged with who spoke it."
                 : "Each utterance is tagged with its language and flag.")
        }
    }

    // MARK: - Refinement

    @ViewBuilder
    private var refinementSection: some View {
        @Bindable var settings = settings

        Section {
            Toggle("Refine translations", isOn: $settings.refineEnabled)

            if settings.refineEnabled {
                Picker("Tone", selection: $settings.formality) {
                    ForEach(Formality.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Glossary")
                        .font(.subheadline.weight(.semibold))
                    Text("One rule per line, e.g. \"OpenAI => OpenAI\" to keep a term, or \"小米 => Xiaomi\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $settings.glossaryText)
                        .frame(minHeight: 88)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .overlay(alignment: .topLeading) {
                            if settings.glossaryText.isEmpty {
                                Text("term => translation")
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
        } header: {
            Text("Translation refinement")
        } footer: {
            Text("After each turn finishes, a text model (\(TranslationRefiner.model)) polishes the translation for fluency, tone, glossary terms, and consistency with earlier turns. This makes a separate billed API call per turn. Turn off to use the raw real-time translation only.")
        }
    }

    // MARK: - Audio & Recognition

    @ViewBuilder
    private var audioRecognitionSection: some View {
        @Bindable var settings = settings

        Section {
            Picker("Microphone scenario", selection: $settings.micScenario) {
                ForEach(MicScenario.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            Text(settings.micScenario.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Auto-level mixed speakers", selection: $settings.autoLevel) {
                ForEach(AutoLevel.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            Text(settings.autoLevel.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Audio & Recognition")
        } footer: {
            Text("Tune these if turns feel slow to appear or if a second speaker is harder to recognize. Changes apply on the next session.")
        }
    }

    // MARK: - Usage

    @ViewBuilder
    private var usageSection: some View {
        Section {
            UsageRow(
                title: "Today",
                minutes: usage.todayMinutes,
                cost: usage.todayCost,
                emphasis: true
            )
            UsageRow(
                title: "Yesterday",
                minutes: usage.yesterdayMinutes,
                cost: usage.yesterdayCost
            )
            UsageRow(
                title: "All time",
                minutes: usage.totalMinutes,
                cost: usage.totalCost
            )

            UsageChart(days: usage.last7Days)
                .frame(height: 110)
                .padding(.vertical, 4)

            Button(role: .destructive) {
                confirmResetUsage = true
            } label: {
                Label("Reset usage history", systemImage: "trash")
            }
        } header: {
            Text("Usage")
        } footer: {
            Text("Estimated from session duration at the OpenAI list price (\(priceString(UsageTracker.pricePerMinute)) / min). OpenAI's official billing dashboard is authoritative.")
        }
    }

    private func priceString(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = (amount < 1 ? 3 : 2)
        f.maximumFractionDigits = (amount < 1 ? 3 : 2)
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

private struct UsageRow: View {
    let title: String
    let minutes: Double
    let cost: Double
    var emphasis: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(emphasis ? .semibold : .regular)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(minuteString)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(costString)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var minuteString: String {
        if minutes < 1 { return String(format: "%.1f sec", minutes * 60) }
        return String(format: "%.1f min", minutes)
    }

    private var costString: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = (cost < 0.01 ? 4 : 2)
        return f.string(from: NSNumber(value: cost)) ?? "$\(cost)"
    }
}

private struct UsageChart: View {
    let days: [DailyUsage]

    var body: some View {
        Chart(days) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Minutes", day.minutes)
            )
            .foregroundStyle(barColor(day))
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine()
                AxisValueLabel()
                    .font(.caption2)
            }
        }
    }

    private func barColor(_ day: DailyUsage) -> Color {
        let isToday = Calendar.current.isDateInToday(day.date)
        return isToday ? .green : .blue.opacity(0.7)
    }
}
