import SwiftUI

/// First-launch onboarding. Walks the user through:
/// 1. What BabelTable does
/// 2. The BYOK / pricing reality of using OpenAI directly
/// 3. Pasting an API key (with a link to OpenAI's dashboard)
/// 4. Choosing primary and secondary languages
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 0
    @State private var keyDraft: String = ""
    @State private var isTestingKey = false
    @State private var keyTestError: String?

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 16)
                .padding(.horizontal, 24)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: costStep
                case 2: keyStep
                default: languagesStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            ))

            controls
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .onAppear {
            // If a key is already in the Keychain (e.g. when this onboarding
            // is being replayed from Settings), pre-fill it so the user does
            // not have to re-paste.
            if keyDraft.isEmpty { keyDraft = settings.apiKey }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var welcomeStep: some View {
        OnboardingPage(
            icon: "bubble.left.and.bubble.right.fill",
            iconColor: .green,
            showAppIcon: true,
            title: "Welcome to BabelTable",
            subtitle: "Real-time speech translation\nbetween two people."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "person.2.fill",
                    color: .green,
                    title: "Two-way conversation",
                    description: "Speak naturally in either language. The model auto-detects who is speaking which."
                )
                FeatureRow(
                    icon: "rectangle.split.1x2.fill",
                    color: .blue,
                    title: "Two layouts",
                    description: "Face-to-face across the table, or chat-style sitting side by side."
                )
                FeatureRow(
                    icon: "tray.full.fill",
                    color: .orange,
                    title: "Archive every chat",
                    description: "Each conversation is saved on this device for you to revisit."
                )
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var costStep: some View {
        OnboardingPage(
            icon: "dollarsign.circle.fill",
            iconColor: .orange,
            title: "Bring Your Own Key",
            subtitle: "BabelTable runs on OpenAI's\ngpt-realtime-translate model."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                InfoBox(
                    icon: "creditcard.fill",
                    color: .orange,
                    title: "Pricing",
                    message: "About **$0.07 per minute** of conversation. We run two parallel translation sessions (one per language) so live audio is billed twice — that's the OpenAI list price, not a BabelTable markup."
                )
                InfoBox(
                    icon: "lock.shield.fill",
                    color: .green,
                    title: "Your key, your device",
                    message: "Your API key is stored only on this device in the iOS Keychain. BabelTable has no backend and never sees your traffic."
                )
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var keyStep: some View {
        OnboardingPage(
            icon: "key.fill",
            iconColor: .yellow,
            title: "Paste your API key",
            subtitle: "Need one? Visit OpenAI's\ndashboard to create a key."
        ) {
            VStack(spacing: 16) {
                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                    HStack {
                        Image(systemName: "safari.fill")
                        Text("Open OpenAI Dashboard")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .padding(14)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
                .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("sk-…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                        .onChange(of: keyDraft) { keyTestError = nil }
                    HStack {
                        Button {
                            if let s = UIPasteboard.general.string {
                                keyDraft = s.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }
                    if let keyTestError {
                        Label(keyTestError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var languagesStep: some View {
        @Bindable var settings = settings

        OnboardingPage(
            icon: "globe",
            iconColor: .blue,
            title: "Pick your languages",
            subtitle: "You can change these any time\nfrom Settings."
        ) {
            VStack(spacing: 16) {
                LanguageCard(
                    title: "Your language",
                    description: "Translations into this language are shown to you.",
                    selection: $settings.primaryLanguageCode,
                    accent: .green
                )
                LanguageCard(
                    title: "Their language",
                    description: "Translations into this language are shown to the other speaker.",
                    selection: $settings.secondaryLanguageCode,
                    accent: .blue
                )
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Controls + chrome

    @ViewBuilder
    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.accentColor : Color.gray.opacity(0.25))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
                    .animation(.easeOut(duration: 0.25), value: step)
            }
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                advance()
            } label: {
                Text(primaryActionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(primaryActionEnabled ? Color.accentColor : Color.gray.opacity(0.4),
                                in: .capsule)
                    .foregroundStyle(.white)
            }
            .disabled(!primaryActionEnabled)

            if step > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
                } label: {
                    Text("Back")
                        .font(.subheadline)
                }
            } else {
                // Reserve the same vertical space so layout doesn't jump.
                Color.clear.frame(height: 24)
            }
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    private var backgroundGradient: LinearGradient {
        let colors: [Color] = switch step {
        case 0: [.green.opacity(0.15), .clear]
        case 1: [.orange.opacity(0.15), .clear]
        case 2: [.yellow.opacity(0.12), .clear]
        default: [.blue.opacity(0.15), .clear]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .center)
    }

    private var primaryActionTitle: String {
        switch step {
        case 0: "Continue"
        case 1: "Next: add your key"
        case 2: isTestingKey ? "Testing connection…" : "Test connection & continue"
        default: "Start translating"
        }
    }

    private var primaryActionEnabled: Bool {
        switch step {
        case 2: !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTestingKey
        default: true
        }
    }

    private func advance() {
        switch step {
        case 2:
            // The key is only saved after a successful connection test.
            let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            isTestingKey = true
            keyTestError = nil
            Task { @MainActor in
                switch await APIKeyValidator.validate(key) {
                case .valid:
                    settings.apiKey = key
                    isTestingKey = false
                    withAnimation(.easeInOut(duration: 0.3)) { step += 1 }
                case .invalid:
                    keyTestError = "OpenAI rejected this key. Check for typos, or create a new one from the dashboard."
                    isTestingKey = false
                case .unreachable(let detail):
                    keyTestError = "Could not reach OpenAI to verify the key (\(detail)). Check your connection and try again."
                    isTestingKey = false
                }
            }
        case totalSteps - 1:
            settings.hasCompletedOnboarding = true
            dismiss()
            return
        default:
            withAnimation(.easeInOut(duration: 0.3)) {
                step = min(step + 1, totalSteps - 1)
            }
        }
    }
}

// MARK: - Building blocks

private struct OnboardingPage<Content: View>: View {
    let icon: String
    let iconColor: Color
    /// Show the real app icon as the hero instead of an SF Symbol.
    var showAppIcon: Bool = false
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if showAppIcon {
                    Image("AppIconDisplay")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .padding(.top, 32)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .padding(.top, 32)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                content()
                    .padding(.top, 12)

                Spacer(minLength: 16)
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct InfoBox: View {
    let icon: String
    let color: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(.init(message))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
}

private struct LanguageCard: View {
    let title: String
    let description: String
    @Binding var selection: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(title, selection: $selection) {
                ForEach(SupportedLanguages.outputs) { lang in
                    Text("\(lang.nativeName) · \(lang.name)").tag(lang.code)
                }
            }
            .pickerStyle(.menu)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.12), in: .rect(cornerRadius: 10))
            .tint(accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }
}
