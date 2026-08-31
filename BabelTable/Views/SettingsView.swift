import Charts
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UsageTracker.self) private var usage
    @Environment(TranslationCoordinator.self) private var coordinator

    @State private var apiKeyDraft: String = ""
    @State private var apiKeyVisible: Bool = false
    @State private var saved = false
    @State private var isTestingKey = false
    @State private var keyTestError: String?
    @State private var showOnboarding = false
    @State private var confirmResetUsage = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(BabelTheme.primary)
                        .frame(width: 46, height: 46)
                        .background(BabelTheme.primarySoft, in: .rect(cornerRadius: BabelTheme.smallRadius))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Conversation setup")
                            .font(.headline)
                        Text("Choose the essentials here. Advanced translation and audio controls are further below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Label(settings.hasAPIKey ? "API key ready" : "API key required",
                      systemImage: settings.hasAPIKey ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(settings.hasAPIKey ? BabelTheme.local : BabelTheme.warning)

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
                    if isTestingKey {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button(saved ? "Saved" : "Save") {
                        saveKeyAfterTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTestingKey)
                }

                if let keyTestError {
                    Label(keyTestError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                    Label("Open OpenAI API keys dashboard", systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                }
            } header: {
                Label("Connection", systemImage: "key.fill")
            } footer: {
                Text("Tested against OpenAI before saving, then stored securely in the iOS Keychain on this device.")
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
                Label("Languages", systemImage: "globe")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Two simultaneous translation sessions run — one for each language. The model auto-detects who is speaking which.")
                    if coordinator.status == .running || coordinator.status == .reconnecting {
                        Text("A session is live — language changes take effect on the next session.")
                    }
                }
            }

            labelsSection

            layoutSection

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
                Label("Diagnostics", systemImage: "stethoscope")
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
                Label("Help", systemImage: "questionmark.circle")
            }

            Section {
                HStack(spacing: 12) {
                    Image("AppIconDisplay")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BabelTable")
                            .font(.headline)
                        Text(versionString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                LabeledContent("Model", value: "gpt-realtime-translate")
                LabeledContent("Sample rate", value: "24 kHz PCM16")
                LabeledContent("List price", value: priceString(UsageTracker.pricePerMinute) + " / min")
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .scrollContentBackground(.hidden)
        .background(BabelTheme.pageBackground)
        .listSectionSpacing(18)
        .navigationTitle("Settings")
        .onAppear {
            apiKeyDraft = settings.apiKey
            keyTestError = nil
        }
        .onChange(of: apiKeyDraft) { keyTestError = nil }
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
            Label("Conversation labels", systemImage: "person.2.fill")
        } footer: {
            Text(settings.speakerLabelStyle == .speaker
                 ? "Each utterance is tagged with who spoke it."
                 : "Each utterance is tagged with its language and flag.")
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var layoutSection: some View {
        @Bindable var settings = settings

        Section {
            Picker("Layout", selection: $settings.displayMode) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        } header: {
            Label("Display", systemImage: "rectangle.split.2x1")
        } footer: {
            Text("Face-to-face rotates the top panel for the person sitting across the table. Same screen shows one chat-style list for both of you.")
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
            HStack {
                Label("Translation refinement", systemImage: "sparkles")
                Spacer()
                Text("OPTIONAL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
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
            HStack {
                Label("Audio & Recognition", systemImage: "waveform")
                Spacer()
                Text("ADVANCED")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
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
            Label("Usage", systemImage: "chart.bar.fill")
        } footer: {
            Text("Estimated from session duration at the OpenAI list price (\(priceString(UsageTracker.pricePerMinute)) / min). OpenAI's official billing dashboard is authoritative.")
        }
    }

    /// Saves the key only after a successful connection test against OpenAI.
    private func saveKeyAfterTest() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isTestingKey = true
        keyTestError = nil
        Task { @MainActor in
            switch await APIKeyValidator.validate(key) {
            case .valid:
                settings.apiKey = key
                saved = true
                isTestingKey = false
                try? await Task.sleep(for: .seconds(1.5))
                saved = false
            case .invalid:
                keyTestError = "OpenAI rejected this key. Check for typos, or create a new one from the dashboard."
                isTestingKey = false
            case .unreachable(let detail):
                keyTestError = "Could not reach OpenAI to verify the key (\(detail)). Check your connection and try again."
                isTestingKey = false
            }
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

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
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
            .clipShape(.rect(cornerRadius: 4))
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
        return isToday ? BabelTheme.local : BabelTheme.remote.opacity(0.7)
    }
}
