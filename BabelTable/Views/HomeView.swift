import SwiftUI

struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.openURL) private var openURL

    @State private var showingSettings = false

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch settings.displayMode {
                    case .faceToFace:
                        faceToFaceLayout
                    case .chat:
                        chatLayout
                    }
                }

                Divider()

                controlBar
                    .padding(.vertical, 12)
                    .background(.thinMaterial)
            }
            .navigationTitle("BabelTable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        toggleDisplayMode()
                    } label: {
                        Image(systemName: settings.displayMode == .faceToFace
                              ? "bubble.left.and.bubble.right"
                              : "rectangle.split.1x2")
                    }
                    .accessibilityLabel(settings.displayMode == .faceToFace
                                        ? "Switch to chat layout"
                                        : "Switch to face-to-face layout")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        coordinator.newConversation()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New conversation")
                    .disabled(!coordinator.hasContent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showingSettings = false
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .accessibilityLabel("Close settings")
                            }
                        }
                }
            }
            .alert(currentError?.title ?? "Translation error",
                   isPresented: errorBinding,
                   actions: {
                       if let error = currentError {
                           switch error.recovery {
                           case .openURL(let url):
                               Button(error.recoveryTitle ?? "Learn more") {
                                   coordinator.dismissError()
                                   openURL(url)
                               }
                           case .openSettings:
                               Button(error.recoveryTitle ?? "Open Settings") {
                                   coordinator.dismissError()
                                   showingSettings = true
                               }
                           case .none:
                               EmptyView()
                           }
                       }
                       Button("OK", role: .cancel) {
                           coordinator.dismissError()
                       }
                   },
                   message: {
                       if let error = currentError {
                           Text(error.message)
                       }
                   })
        }
    }

    // MARK: - Layouts

    /// Panel header: the speaker's name in speaker-label mode, else the
    /// language's native name.
    private func panelTitle(forSpeaker speaker: String, language: Language) -> String {
        settings.speakerLabelStyle == .speaker ? speaker : language.nativeName
    }

    @ViewBuilder
    private var faceToFaceLayout: some View {
        VStack(spacing: 0) {
            // Top panel — rotated 180° for the person sitting opposite.
            TranscriptPanel(
                title: panelTitle(forSpeaker: settings.secondarySpeakerName,
                                  language: settings.secondaryLanguage),
                languageCode: coordinator.secondaryLanguageCode,
                text: coordinator.secondaryTranscript,
                accent: .blue,
                isRunning: coordinator.status == .running
            )
            .rotationEffect(.degrees(180))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom panel — for the user holding the phone.
            TranscriptPanel(
                title: panelTitle(forSpeaker: settings.primarySpeakerName,
                                  language: settings.primaryLanguage),
                languageCode: coordinator.primaryLanguageCode,
                text: coordinator.primaryTranscript,
                accent: .green,
                isRunning: coordinator.status == .running
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var chatLayout: some View {
        ChatView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Control bar

    private func toggleDisplayMode() {
        settings.displayMode = settings.displayMode == .faceToFace ? .chat : .faceToFace
    }

    private var currentError: TranslationError? {
        if case let .error(error) = coordinator.status {
            return error
        }
        return nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: {
                if case .error = coordinator.status { return true }
                return false
            },
            set: { newValue in
                if !newValue { coordinator.dismissError() }
            }
        )
    }

    @ViewBuilder
    private var controlBar: some View {
        HStack(spacing: 16) {
            statusDot
            Spacer()
            actionButton
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: sideSlotWidth, alignment: .trailing)
        }
        .padding(.horizontal)
        .frame(maxWidth: isRegular ? 720 : .infinity)
        .frame(maxWidth: .infinity)
    }

    /// Width of the status / dot side slots — wider on iPad so the action
    /// button stays centered and balanced.
    private var sideSlotWidth: CGFloat { isRegular ? 120 : 80 }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
            .frame(width: sideSlotWidth, alignment: .leading)
            .padding(.leading)
    }

    private var statusColor: Color {
        switch coordinator.status {
        case .idle: return .gray
        case .starting, .stopping, .reconnecting: return .yellow
        case .running: return .red
        case .error: return .orange
        }
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle: return "Idle"
        case .starting: return "Starting…"
        case .running: return "Live"
        case .reconnecting: return "Reconnecting…"
        case .stopping: return "Stopping…"
        case .error: return "Error"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch coordinator.status {
        case .running, .reconnecting, .stopping:
            Button {
                coordinator.stop()
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .font(actionButtonFont)
                    .fixedSize()
                    .padding(.horizontal, actionButtonHPadding)
                    .padding(.vertical, actionButtonVPadding)
                    .background(.red, in: .capsule)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(coordinator.status == .stopping)

        case .idle, .starting, .error:
            Button {
                Task { await coordinator.start() }
            } label: {
                Label("Start", systemImage: "mic.circle.fill")
                    .font(actionButtonFont)
                    .fixedSize()
                    .padding(.horizontal, actionButtonHPadding)
                    .padding(.vertical, actionButtonVPadding)
                    .background(settings.hasAPIKey ? .green : .gray, in: .capsule)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!settings.hasAPIKey || coordinator.status == .starting)
        }
    }

    private var actionButtonFont: Font {
        isRegular ? .title2.weight(.semibold) : .title3.weight(.semibold)
    }

    private var actionButtonHPadding: CGFloat { isRegular ? 32 : 24 }
    private var actionButtonVPadding: CGFloat { isRegular ? 14 : 10 }
}
