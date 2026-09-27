import SwiftUI

struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingSettings = false
    @State private var showingArchive = false

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch settings.displayMode {
                    case .faceToFace: faceToFaceLayout
                    case .chat: ChatView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                sessionConsole
            }
            .background(BabelTheme.pageBackground)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: coordinator.suspendForBackground()
                case .active: coordinator.resumeFromBackground()
                default: break
                }
            }
            .overlay(alignment: .bottom) {
                if let summary = coordinator.sessionSummary {
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: .capsule)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                        .padding(.bottom, isRegular ? 154 : 142)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: coordinator.sessionSummary)
            .navigationTitle("BabelTable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingArchive) { ArchiveView() }
            .sheet(isPresented: $showingSettings) { settingsSheet }
            .alert(currentError?.title ?? "Translation error", isPresented: errorBinding) {
                errorActions
            } message: {
                if let currentError { Text(currentError.message) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showingArchive = true } label: { Image(systemName: "clock.arrow.circlepath") }
                .accessibilityLabel("History")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if coordinator.hasContent {
                ShareLink(item: coordinator.liveCaptionText, subject: Text("BabelTable Live Captions")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share live captions")
            }
            Menu {
                Button { coordinator.newConversation() } label: {
                    Label("New conversation", systemImage: "plus")
                }
                .disabled(!coordinator.hasContent || coordinator.hasUnsavedSession || coordinator.isSessionActive)
                Button { showingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More")
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            SettingsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingSettings = false }
                    }
                }
        }
    }

    private var faceToFaceLayout: some View {
        VStack(spacing: 0) {
            TranscriptPanel(
                title: panelTitle(forSpeaker: settings.secondarySpeakerName, language: coordinator.displayedSecondaryLanguage),
                languageCode: coordinator.secondaryLanguageCode,
                text: coordinator.secondaryTranscript,
                accent: BabelTheme.remote,
                isRunning: coordinator.status == .running,
                isActiveSpeaker: activeLanguageCode == coordinator.displayedPrimaryLanguage.code
            )
            .rotationEffect(.degrees(180))
            conversationAxis
            TranscriptPanel(
                title: panelTitle(forSpeaker: settings.primarySpeakerName, language: coordinator.displayedPrimaryLanguage),
                languageCode: coordinator.primaryLanguageCode,
                text: coordinator.primaryTranscript,
                accent: BabelTheme.local,
                isRunning: coordinator.status == .running,
                isActiveSpeaker: activeLanguageCode == coordinator.displayedSecondaryLanguage.code
            )
        }
        .padding(.horizontal, isRegular ? 20 : 10)
        .padding(.top, 8)
    }

    private var conversationAxis: some View {
        HStack(spacing: 8) {
            Rectangle().fill(BabelTheme.remote.opacity(0.25)).frame(height: 1)
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(7)
                .background(BabelTheme.elevatedBackground, in: .circle)
            Rectangle().fill(BabelTheme.local.opacity(0.25)).frame(height: 1)
        }
        .padding(.vertical, 5)
        .accessibilityHidden(true)
    }

    private func panelTitle(forSpeaker speaker: String, language: Language) -> String {
        settings.speakerLabelStyle == .speaker ? speaker : language.nativeName
    }

    private var activeLanguageCode: String? {
        guard let code = coordinator.openTurn?.sourceLanguageCode else { return nil }
        return SupportedLanguages.normalize(code)
    }

    @ViewBuilder
    private var sessionConsole: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView { consoleContent }
                .frame(maxHeight: 360)
                .background(.regularMaterial)
        } else { consoleContent }
    }

    private var consoleContent: some View {
        VStack(spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(coordinator.displayedPrimaryLanguage.nativeName) ↔ \(coordinator.displayedSecondaryLanguage.nativeName)")
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(statusText).font(.caption).foregroundStyle(statusColor)
                actionButton
            } else {
                HStack(spacing: 8) {
                    LanguagePill(languageCode: coordinator.displayedPrimaryLanguage.code, title: coordinator.displayedPrimaryLanguage.nativeName, tint: BabelTheme.local)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    LanguagePill(languageCode: coordinator.displayedSecondaryLanguage.code, title: coordinator.displayedSecondaryLanguage.nativeName, tint: BabelTheme.remote)
                    Spacer(minLength: 4)
                    StatusPill(title: statusText, systemImage: statusSymbol, tint: statusColor,
                               isAnimated: coordinator.status == .starting || coordinator.status == .paused)
                }

                HStack(spacing: 14) {
                    MicLevelMeter(level: coordinator.micLevel, isActive: coordinator.status == .running)
                    actionButton
                    Button { showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Conversation settings")
                }
            }

            if let failure = coordinator.saveFailure {
                VStack(alignment: .leading, spacing: 8) {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(BabelTheme.warning)
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Retry saving") { coordinator.retrySave() }
                        ShareLink("Share text", item: coordinator.liveCaptionText)
                    }
                }
                .accessibilityIdentifier("save.failure")
            }
            if coordinator.status == .running {
                Picker("Speaking language", selection: Binding(
                    get: { coordinator.speakingPrimary },
                    set: { coordinator.selectSpeaker(primary: $0) })) {
                    Text(coordinator.displayedPrimaryLanguage.nativeName).tag(true)
                    Text(coordinator.displayedSecondaryLanguage.nativeName).tag(false)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("translation.speaker")
            }
            if coordinator.status == .paused {
                Button("Resume conversation") { coordinator.resume() }.buttonStyle(.borderedProminent)
            }
            Text(activityDescription)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if coordinator.status == .idle {
                Button("Prepare offline languages") { showingSettings = true }.font(.caption)
            }
        }
        .frame(maxWidth: isRegular ? 720 : .infinity)
        .padding(.horizontal, BabelTheme.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch coordinator.status {
        case .starting, .running, .paused, .stopping:
            Button { coordinator.stop() } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(isRegular ? .title3.weight(.semibold) : .headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isRegular ? 13 : 11)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(BabelTheme.live)
            .disabled(coordinator.status == .stopping)
        case .idle, .error:
            Button {
                Task { await coordinator.start() }
            } label: {
                Label(dynamicTypeSize.isAccessibilitySize ? "Start" : "Start translating", systemImage: "mic.fill")
                    .font(isRegular ? .title3.weight(.semibold) : .headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isRegular ? 13 : 11)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(BabelTheme.primary)
            .disabled(coordinator.status == .starting || coordinator.hasUnsavedSession)
            .accessibilityIdentifier("translation.start")
        }
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle: "Ready"
        case .starting: "Preparing"
        case .running: "Live"
        case .paused: "Paused"
        case .stopping: "Saving"
        case .error: "Needs attention"
        }
    }

    private var statusSymbol: String {
        switch coordinator.status {
        case .idle: "checkmark.circle.fill"
        case .starting: "cpu"
        case .running: "waveform"
        case .paused: "arrow.trianglehead.2.clockwise.rotate.90"
        case .stopping: "archivebox.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch coordinator.status {
        case .idle: .secondary
        case .starting, .paused: BabelTheme.warning
        case .running: BabelTheme.live
        case .stopping: BabelTheme.primary
        case .error: BabelTheme.warning
        }
    }

    private var activityDescription: String {
        switch coordinator.status {
        case .idle: return "Prepare your languages in Settings, then start an offline conversation."
        case .starting: return "Preparing on-device speech recognition…"
        case .running:
            if let turn = coordinator.openTurn, !turn.sourceText.isEmpty {
                return "Heard: \(String(turn.sourceText.suffix(90)))"
            }
            return "Speak in the selected language. Switch when the other person speaks."
        case .paused: return "Microphone paused. Tap Resume when you are ready to speak."
        case .stopping: return "Saving this conversation to History…"
        case .error: return "Open the alert for recovery options."
        }
    }

    private var currentError: TranslationError? {
        if case let .error(error) = coordinator.status { return error }
        return nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { if case .error = coordinator.status { true } else { false } },
                set: { if !$0 { coordinator.dismissError() } })
    }

    @ViewBuilder
    private var errorActions: some View {
        if let error = currentError {
            switch error.recovery {
            case .openURL(let url):
                Button(error.recoveryTitle ?? "Learn more") { coordinator.dismissError(); openURL(url) }
            case .openSettings:
                Button(error.recoveryTitle ?? "Open Settings") { coordinator.dismissError(); showingSettings = true }
            case .none: EmptyView()
            }
        }
        Button("OK", role: .cancel) { coordinator.dismissError() }
    }
}

private struct MicLevelMeter: View {
    let level: Float
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: isActive ? "waveform" : "mic")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? BabelTheme.local : .secondary)
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Capsule().fill(.secondary.opacity(0.16))
                    Capsule().fill(BabelTheme.local)
                        .frame(height: geometry.size.height * max(0.08, CGFloat(min(max(level, 0), 1))))
                }
            }
            .frame(width: 8, height: 28)
        }
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(isActive ? "\(Int(level * 100)) percent" : "Inactive")
    }
}
