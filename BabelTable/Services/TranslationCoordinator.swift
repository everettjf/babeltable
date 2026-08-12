import Foundation
import NaturalLanguage
import Observation
import UIKit

/// Orchestrates the live translation pipeline:
///   - One `AudioCaptureService` reading the mic at 24 kHz PCM16.
///   - Two `RealtimeTranslator` WebSockets, one targeting each language.
///   - Routes deltas into two on-screen transcripts and persists to a session
///     when the user stops.
@Observable
@MainActor
final class TranslationCoordinator {

    enum Status: Sendable, Equatable {
        case idle
        case starting
        case running
        case reconnecting
        case stopping
        case error(TranslationError)
    }

    private(set) var status: Status = .idle

    private(set) var networkCondition: ConnectivityMonitor.Condition = .online

    var degradationMessage: String? {
        switch networkCondition {
        case .offline: "Offline — conversation is paused and the draft is saved."
        case .constrained: "Weak network — realtime translation continues without optional refinement."
        case .online: nil
        }
    }

    /// Streaming text for the panel showing translations *into* primary language.
    /// The user reading this panel sees what the other speaker said in their own language.
    private(set) var primaryTranscript: String = ""
    /// Streaming text for the panel showing translations into the secondary language.
    private(set) var secondaryTranscript: String = ""

    /// Last detected source-language transcript (auto-detected by Whisper).
    private(set) var lastInputTranscript: String = ""

    /// Chronological chat-mode list. Each turn = one detected utterance plus
    /// the matching translation into the *other* language.
    private(set) var chatTurns: [ChatTurn] = []

    private(set) var primaryLanguageCode: String = "en"
    private(set) var secondaryLanguageCode: String = "zh"

    private let settings: AppSettings
    private let store: SessionStore
    private let usage: UsageTracker

    private let audio = AudioCaptureService()
    private let connectivity = ConnectivityMonitor()
    private let refiner = TranslationRefiner()
    private var primaryTranslator: RealtimeTranslator?
    private var secondaryTranslator: RealtimeTranslator?

    // Auto-reconnect state. A recoverable failure (connection drop, rate limit)
    // rebuilds both sockets after a backoff instead of dropping the user to the
    // error screen. `awaitingReconnect` is true during the backoff sleep so the
    // flood of follow-on send failures from the dying socket is ignored.
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var awaitingReconnect = false
    private static let maxReconnectAttempts = 3

    /// Sockets that have reported `.ready` since the last (re)build. During a
    /// reconnect we wait for *both* before going back to `.running`, so one
    /// live socket doesn't make us drop audio meant for the other.
    private var readyPanels: Set<Panel> = []

    /// True after the app went to background mid-session. Without a
    /// background-audio entitlement iOS kills capture and the sockets, so we
    /// tear down cleanly and rebuild on return to the foreground.
    private var suspendedForBackground = false

    /// True while the system has interrupted capture (call/Siri). Separate
    /// from `status` so a socket reconnect completing *during* an
    /// interruption doesn't flip us back to `.running` with a dead mic.
    private var audioInterrupted = false

    /// Smoothed mic loudness 0…1 for the level meter; 0 when not capturing.
    private(set) var micLevel: Float = 0

    /// One-line "session saved · duration · cost" notice shown briefly after
    /// a session is persisted. Nil when nothing to show.
    private(set) var sessionSummary: String?

    /// Stable id for the in-progress session. Drafts are persisted
    /// incrementally (each finished turn, on backgrounding) so a crash or
    /// kill loses at most the currently-open turn, and the final save
    /// overwrites the draft.
    private var draftSessionID: UUID?

    /// Display caps so an hours-long session doesn't turn the transcript
    /// panels into a single unbounded Text that re-layouts on every delta.
    /// Full content is still archived via the per-line buffers.
    private static let maxPanelChars = 4000
    private static let maxInputChars = 2000

    private var sessionStartedAt: Date?
    private var primaryLines: [TranscriptLine] = []
    private var secondaryLines: [TranscriptLine] = []
    private var inputLines: [TranscriptLine] = []

    // Chat-turn streaming state. `openTurn` is the input-receiving slot;
    // `drainingTurn` is a turn whose input has just been closed but whose
    // translation may still be streaming. Holding the previous turn in a
    // draining slot prevents late translation deltas from leaking into the
    // next turn — the OpenAI translations endpoint emits no item_id we
    // could use to demux, so we route by temporal order.
    private(set) var openTurn: ChatTurn?
    private(set) var drainingTurn: ChatTurn?
    private var openTurnLastInputAt: Date = .distantPast
    private var openTurnTranslatedFromPanel: Panel?
    private var drainingTurnTranslatedFromPanel: Panel?
    private var drainingTurnLastOutputAt: Date = .distantPast

    /// If draining's output has been quiet longer than this, the next output
    /// delta likely belongs to the new openTurn — promote draining first.
    private static let drainingContinuityWindow: TimeInterval = 0.5

    init(settings: AppSettings, store: SessionStore, usage: UsageTracker) {
        self.settings = settings
        self.store = store
        self.usage = usage

        audio.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in self?.micLevel = level }
        }
        audio.onInterruption = { [weak self] event in
            Task { @MainActor [weak self] in self?.handleInterruption(event) }
        }
        audio.onMediaServicesReset = { [weak self] in
            Task { @MainActor [weak self] in self?.handleMediaServicesReset() }
        }
        connectivity.onChange = { [weak self] condition in
            Task { @MainActor [weak self] in self?.handleConnectivity(condition) }
        }
        connectivity.start()
    }

    // MARK: - Public

    func dismissError() {
        if case .error = status { status = .idle }
    }

    /// True when there is anything visible in the home view (an in-flight or
    /// completed turn, or accumulated transcript text). Used to decide whether
    /// the "new conversation" toolbar action should be enabled.
    var hasContent: Bool {
        !chatTurns.isEmpty
            || openTurn != nil
            || drainingTurn != nil
            || !primaryLines.isEmpty
            || !secondaryLines.isEmpty
            || !primaryTranscript.isEmpty
            || !secondaryTranscript.isEmpty
    }

    /// Snapshot suitable for Messages, AirDrop, Notes, or a live meeting chat.
    /// It includes in-flight turns, so sharing never requires ending a session.
    var liveCaptionText: String {
        let turns = chatTurns + [drainingTurn, openTurn].compactMap { $0 }
        let body = turns.map { turn in
            let source = turn.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            let translation = turn.bestTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
            let time = turn.startedAt.formatted(date: .omitted, time: .standard)
            return ["[\(time)] \(source)", translation.isEmpty ? nil : "→ \(translation)"]
                .compactMap { $0 }
                .joined(separator: "\n")
        }.joined(separator: "\n\n")
        return "BabelTable Live Captions\n\n\(body)"
    }

    /// Stop any running session (which saves it to the archive), then clear
    /// the in-memory display so the home view is ready for a fresh chat.
    /// No-op when there is nothing on screen to avoid empty archive entries.
    func newConversation() {
        guard hasContent else { return }

        if status == .running || status == .starting || status == .reconnecting {
            stop()
        }

        chatTurns = []
        openTurn = nil
        drainingTurn = nil
        primaryTranscript = ""
        secondaryTranscript = ""
        lastInputTranscript = ""
        primaryLines = []
        secondaryLines = []
        inputLines = []
        openTurnTranslatedFromPanel = nil
        drainingTurnTranslatedFromPanel = nil
        drainingTurnLastOutputAt = .distantPast
        openTurnLastInputAt = .distantPast
        sessionSummary = nil
        micLevel = 0
    }

    func start() async {
        // A previous error should not block restarting.
        if case .error = status { status = .idle }
        guard status != .running, status != .starting else { return }

        guard networkCondition != .offline else {
            status = .error(TranslationError(raw: "You are offline. BabelTable will be ready when the network returns."))
            return
        }

        guard !settings.apiKey.isEmpty else {
            status = .error(TranslationError(raw: "Add your OpenAI API key in Settings."))
            diagLog(.error, tag: "Coord", "Start blocked: no API key")
            return
        }

        diagLog(.info, tag: "Coord", "Start requested: primary=\(settings.primaryLanguageCode), secondary=\(settings.secondaryLanguageCode), mic=\(settings.micScenario.rawValue), autoLevel=\(settings.autoLevel.rawValue)")
        status = .starting

        // Reset state for a fresh chat.
        primaryTranscript = ""
        secondaryTranscript = ""
        lastInputTranscript = ""
        primaryLines = []
        secondaryLines = []
        inputLines = []
        chatTurns = []
        openTurn = nil
        drainingTurn = nil
        openTurnTranslatedFromPanel = nil
        drainingTurnTranslatedFromPanel = nil
        drainingTurnLastOutputAt = .distantPast
        reconnectAttempts = 0
        awaitingReconnect = false
        suspendedForBackground = false
        audioInterrupted = false
        readyPanels = []
        sessionSummary = nil
        micLevel = 0
        sessionStartedAt = Date()
        draftSessionID = UUID()
        let sessionLanguages = SessionLanguagePair(
            primary: settings.primaryLanguageCode,
            secondary: settings.secondaryLanguageCode
        )
        primaryLanguageCode = sessionLanguages.primary
        secondaryLanguageCode = sessionLanguages.secondary

        // This app is used lying on a table mid-conversation; the screen
        // must not auto-lock while a session is live (that would suspend the
        // app and kill capture). Cleared in finishSession().
        UIApplication.shared.isIdleTimerDisabled = true

        buildAndConnectTranslators()

        let captureMode: AudioCaptureService.CaptureMode = (settings.autoLevel == .on) ? .voiceChat : .measurement

        do {
            try await audio.start(mode: captureMode)
            // A translator may have failed during the await above. Honor the
            // resulting state rather than clobbering it with .running.
            switch status {
            case .starting:
                status = .running
                diagLog(.info, tag: "Coord", "Audio started, status=running")
            case .reconnecting:
                // A recoverable error fired during startup; the scheduled
                // reconnect will rebuild the sockets and needs the mic running.
                diagLog(.info, tag: "Coord", "Audio started during reconnect")
            default:
                // Fatal error during startup — already torn down; stop the mic
                // that just finished starting.
                audio.stop()
            }
        } catch {
            diagLog(.error, tag: "Audio", "Start failed: \(error.localizedDescription)")
            audio.stop()
            tearDownConnections()
            reconnectTask?.cancel()
            reconnectTask = nil
            awaitingReconnect = false
            UIApplication.shared.isIdleTimerDisabled = false
            status = .error(TranslationError(raw: error.localizedDescription))
        }
    }

    /// Called when the app goes to background mid-session. Without a
    /// background-audio entitlement iOS suspends capture and kills the
    /// sockets, so we tear down cleanly (persisting a draft) and resume when
    /// the app returns — nothing the user said is lost.
    func suspendForBackground() {
        guard status == .running || status == .starting || status == .reconnecting else { return }
        guard !suspendedForBackground else { return }
        diagLog(.info, tag: "Coord", "Backgrounded; suspending session")
        suspendedForBackground = true
        // The interruption state is superseded — resume rebuilds the engine
        // from scratch rather than continuing the interrupted one.
        audioInterrupted = false
        reconnectTask?.cancel()
        reconnectTask = nil
        awaitingReconnect = false
        persistDraft()
        tearDownConnections()
        audio.stop()
        micLevel = 0
        status = .reconnecting
    }

    /// Called when the app returns to the foreground after
    /// `suspendForBackground()`. Rebuilds the sockets and restarts capture;
    /// status flips back to `.running` once both sockets report ready.
    func resumeFromBackground() {
        guard suspendedForBackground, status == .reconnecting else { return }
        suspendedForBackground = false
        diagLog(.info, tag: "Coord", "Foregrounded; resuming session")
        buildAndConnectTranslators()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.audio.restart()
            } catch {
                self.failSession(TranslationError(raw: "Microphone restart failed: \(error.localizedDescription)"))
            }
        }
    }

    func stop() {
        guard status == .running || status == .starting || status == .reconnecting else { return }
        diagLog(.info, tag: "Coord", "Stop requested")
        status = .stopping
        finishSession()
        status = .idle
    }

    /// React to a translator/socket failure. Recoverable failures (connection
    /// drop, rate limit) trigger a backoff reconnect that keeps the mic running;
    /// persistent ones (quota, auth) tear everything down and surface the alert.
    ///
    /// Only the first error in a burst is acted on: a dead socket emits a
    /// continuous flood of "Socket is not connected" send failures, and without
    /// the guards below each one would re-trigger handling. `awaitingReconnect`
    /// covers the flood during the backoff window.
    private func failSession(_ error: TranslationError) {
        guard status == .running || status == .starting || status == .reconnecting else { return }
        // While backgrounded everything is already torn down and will be
        // rebuilt on foregrounding — late errors from dying sockets are moot.
        guard !suspendedForBackground else { return }
        // A reconnect is already queued — ignore follow-on errors from the
        // dying socket until that attempt resolves.
        guard !awaitingReconnect else { return }

        if case .retry = Self.reconnectDecision(
            afterCompletedAttempts: reconnectAttempts,
            error: error
        ) {
            scheduleReconnect(error)
            return
        }

        diagLog(.error, tag: "Coord", "Session failed: \(error.kind) — \(error.message)")
        finishSession()
        status = .error(error)
    }

    /// Close the current sockets (keeping the mic running) and rebuild them
    /// after a backoff delay. The mic audio captured during the gap is dropped.
    private func scheduleReconnect(_ error: TranslationError) {
        reconnectAttempts += 1
        let attempt = reconnectAttempts
        let delay = Self.backoffDelay(forAttempt: attempt, kind: error.kind)
        diagLog(.info, tag: "Coord", "Reconnect attempt \(attempt)/\(Self.maxReconnectAttempts) in \(delay)s after \(error.kind)")

        awaitingReconnect = true
        status = .reconnecting
        teardownTranslators()

        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.performReconnect()
        }
    }

    private func performReconnect() {
        // The user may have stopped during the backoff sleep.
        guard status == .reconnecting, awaitingReconnect else { return }
        awaitingReconnect = false
        diagLog(.info, tag: "Coord", "Rebuilding translators (attempt \(reconnectAttempts))")
        buildAndConnectTranslators()
    }

    // `internal` (not `private`) so unit tests can verify the backoff schedule
    // via `@testable import`. Pure function: no instance state touched.
    static func backoffDelay(forAttempt attempt: Int, kind: TranslationError.Kind) -> TimeInterval {
        // Rate limits need breathing room; retrying too soon just re-trips them.
        if kind == .rateLimit { return 5 }
        // Connection drops: 1s, 2s, 4s … capped at 8s.
        return min(pow(2.0, Double(attempt - 1)), 8)
    }

    enum ReconnectDecision: Equatable {
        case retry(attempt: Int, delay: TimeInterval)
        case fail
    }

    static func reconnectDecision(
        afterCompletedAttempts attempts: Int,
        error: TranslationError
    ) -> ReconnectDecision {
        guard error.isRecoverable, attempts < maxReconnectAttempts else { return .fail }
        let nextAttempt = attempts + 1
        return .retry(
            attempt: nextAttempt,
            delay: backoffDelay(forAttempt: nextAttempt, kind: error.kind)
        )
    }

    /// Stop audio, close sockets, finalize pending turns, record usage, and
    /// persist the session. Shared by a clean stop and a fatal error.
    private func finishSession() {
        reconnectTask?.cancel()
        reconnectTask = nil
        awaitingReconnect = false
        reconnectAttempts = 0
        suspendedForBackground = false
        audioInterrupted = false
        readyPanels = []
        UIApplication.shared.isIdleTimerDisabled = false
        audio.stop()
        tearDownConnections()
        micLevel = 0

        // Finalize any pending turns in chronological order: draining first
        // (its input was already closed earlier), then the still-open turn.
        if let turn = drainingTurn {
            finalize(turn)
            drainingTurn = nil
            drainingTurnTranslatedFromPanel = nil
        }
        if let turn = openTurn {
            finalize(turn)
            openTurn = nil
            openTurnTranslatedFromPanel = nil
        }

        // Record usage for this session, regardless of whether transcripts arrived.
        var elapsed: TimeInterval = 0
        if let startedAt = sessionStartedAt {
            elapsed = Date().timeIntervalSince(startedAt)
            usage.recordSession(durationSeconds: elapsed)
        }

        // Persist the session if there is anything to save. Reuses the draft
        // id so this overwrites the incrementally-saved draft in place.
        if let startedAt = sessionStartedAt,
           !primaryLines.isEmpty || !secondaryLines.isEmpty || !inputLines.isEmpty || !chatTurns.isEmpty {
            let session = ChatSession(
                id: draftSessionID ?? UUID(),
                startedAt: startedAt,
                endedAt: Date(),
                primaryLanguageCode: primaryLanguageCode,
                secondaryLanguageCode: secondaryLanguageCode,
                primaryLines: primaryLines,
                secondaryLines: secondaryLines,
                chatTurns: chatTurns
            )
            store.save(session)
            showSessionSummary(elapsed: elapsed)
        }

        sessionStartedAt = nil
        draftSessionID = nil
    }

    /// Brief on-screen confirmation that the conversation was archived,
    /// including its estimated cost. Clears itself after a few seconds.
    private func showSessionSummary(elapsed: TimeInterval) {
        let cost = (elapsed / 60) * UsageTracker.pricePerMinute
        let summary = String(format: "Session saved · %d:%02d · ≈ $%.2f",
                             Int(elapsed) / 60, Int(elapsed) % 60, cost)
        sessionSummary = summary
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, self.sessionSummary == summary else { return }
            self.sessionSummary = nil
        }
    }

    /// Incrementally persist the in-progress session so a crash, kill, or
    /// backgrounding loses at most the currently-open turn. The final save in
    /// `finishSession()` overwrites this draft (same id).
    private func persistDraft() {
        guard let startedAt = sessionStartedAt, let id = draftSessionID,
           !primaryLines.isEmpty || !secondaryLines.isEmpty || !inputLines.isEmpty || !chatTurns.isEmpty else { return }
        store.save(ChatSession(
            id: id,
            startedAt: startedAt,
            endedAt: nil,
            primaryLanguageCode: primaryLanguageCode,
            secondaryLanguageCode: secondaryLanguageCode,
            primaryLines: primaryLines,
            secondaryLines: secondaryLines,
            chatTurns: chatTurns
        ))
    }

    // MARK: - Private

    private enum Panel { case primary, secondary }

    /// Build both target-language sockets, wire mic fan-out, and connect.
    /// Used both on a fresh start and on reconnect; relies on
    /// `primaryLanguageCode`/`secondaryLanguageCode` already being set.
    private func buildAndConnectTranslators() {
        // New sockets must both re-report ready before we count as live.
        readyPanels = []

        let noiseReduction: RealtimeTranslator.NoiseReduction
        switch settings.micScenario {
        case .closeSingle: noiseReduction = .nearField
        case .desktopTwo: noiseReduction = .farField
        }

        // Build translators with @Sendable callbacks that hop to MainActor.
        let primary = RealtimeTranslator(
            apiKey: settings.apiKey,
            targetLanguageCode: primaryLanguageCode,
            noiseReduction: noiseReduction
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event, panel: .primary)
            }
        }

        let secondary = RealtimeTranslator(
            apiKey: settings.apiKey,
            targetLanguageCode: secondaryLanguageCode,
            noiseReduction: noiseReduction
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event, panel: .secondary)
            }
        }

        primaryTranslator = primary
        secondaryTranslator = secondary

        primary.connect()
        secondary.connect()

        // Mic chunks fan out to both WebSockets.
        audio.onChunk = { [weak primary, weak secondary] data in
            primary?.appendAudio(data)
            secondary?.appendAudio(data)
        }
    }

    /// Close both sockets but leave the mic running. Used for reconnect.
    private func teardownTranslators() {
        primaryTranslator?.close()
        secondaryTranslator?.close()
        primaryTranslator = nil
        secondaryTranslator = nil
    }

    /// Full teardown: stop mic fan-out and close both sockets.
    private func tearDownConnections() {
        audio.onChunk = nil
        teardownTranslators()
    }

    // MARK: - Audio system events

    /// System audio interruption (phone call, Siri, …). The sockets stay
    /// alive; only capture pauses. We reuse the `.reconnecting` status so the
    /// UI shows the session as temporarily degraded rather than live.
    private func handleInterruption(_ event: AudioCaptureService.InterruptionEvent) {
        switch event {
        case .began:
            guard status == .running || status == .reconnecting else { return }
            diagLog(.warn, tag: "Coord", "Audio interrupted; mic paused")
            audioInterrupted = true
            micLevel = 0
            status = .reconnecting
        case .resumed:
            audioInterrupted = false
            // If backgrounded or a socket reconnect is in flight, those paths
            // own the transition back to `.running`.
            guard status == .reconnecting, !awaitingReconnect, !suspendedForBackground else { return }
            diagLog(.info, tag: "Coord", "Audio interruption ended; resuming")
            status = .running
        case .resumeFailed(let message):
            audioInterrupted = false
            guard status == .running || status == .reconnecting else { return }
            failSession(TranslationError(raw: "Microphone restart failed: \(message)"))
        }
    }

    /// Media services were reset: the entire audio stack (and likely the
    /// sockets) is invalid. Rebuild both sides.
    private func handleMediaServicesReset() {
        guard status == .running || status == .starting || status == .reconnecting else { return }
        guard !suspendedForBackground else { return }
        diagLog(.warn, tag: "Coord", "Media services reset; rebuilding audio + sockets")
        teardownTranslators()
        status = .reconnecting
        buildAndConnectTranslators()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.audio.restart()
            } catch {
                self.failSession(TranslationError(raw: "Microphone restart failed: \(error.localizedDescription)"))
            }
        }
    }

    private func handleConnectivity(_ condition: ConnectivityMonitor.Condition) {
        guard condition != networkCondition else { return }
        let previous = networkCondition
        networkCondition = condition

        switch condition {
        case .offline:
            guard status == .running || status == .starting || status == .reconnecting else { return }
            diagLog(.warn, tag: "Network", "Offline; pausing and preserving draft")
            persistDraft()
            reconnectTask?.cancel()
            reconnectTask = nil
            awaitingReconnect = true
            tearDownConnections()
            audio.stop()
            micLevel = 0
            status = .reconnecting
        case .constrained, .online:
            guard previous == .offline, status == .reconnecting, sessionStartedAt != nil,
                  !suspendedForBackground else { return }
            diagLog(.info, tag: "Network", "Connectivity restored; resuming realtime session")
            awaitingReconnect = false
            buildAndConnectTranslators()
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.audio.restart()
                } catch {
                    self.failSession(TranslationError(raw: "Microphone restart failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func handle(event: RealtimeTranslator.Event, panel: Panel) {
        switch event {
        case .state(let s):
            switch s {
            case .ready:
                readyPanels.insert(panel)
                // Back to live only once *both* sockets are up and the mic
                // isn't paused by a system interruption — otherwise audio
                // meant for a dead channel is silently dropped.
                if status == .reconnecting, readyPanels.count == 2, !audioInterrupted {
                    diagLog(.info, tag: "Coord", "Reconnected (both panels ready)")
                    reconnectAttempts = 0
                    awaitingReconnect = false
                    reconnectTask?.cancel()
                    reconnectTask = nil
                    status = .running
                }
            case .failed(let msg):
                diagLog(.error, tag: "Coord", "Translator \(panel) failed: \(msg)")
                failSession(TranslationError(raw: msg))
            default: break
            }
        case .inputDelta(let delta):
            // Both translators emit input transcripts; we use only the primary's
            // copy to avoid duplicate lines.
            guard panel == .primary else { return }
            lastInputTranscript += delta
            if lastInputTranscript.count > Self.maxInputChars {
                lastInputTranscript = String(lastInputTranscript.suffix(Self.maxInputChars))
            }
            appendDelta(delta, to: &inputLines, languageCode: "auto", kind: .input)
            updateChatTurnFromInput(delta: delta)
        case .outputDelta(let delta):
            switch panel {
            case .primary:
                primaryTranscript += delta
                if primaryTranscript.count > Self.maxPanelChars {
                    primaryTranscript = String(primaryTranscript.suffix(Self.maxPanelChars))
                }
                appendDelta(delta, to: &primaryLines, languageCode: primaryLanguageCode, kind: .output)
            case .secondary:
                secondaryTranscript += delta
                if secondaryTranscript.count > Self.maxPanelChars {
                    secondaryTranscript = String(secondaryTranscript.suffix(Self.maxPanelChars))
                }
                appendDelta(delta, to: &secondaryLines, languageCode: secondaryLanguageCode, kind: .output)
            }
            updateChatTurnFromOutput(delta: delta, panel: panel)
        case .error(let msg, let code):
            diagLog(.error, tag: "Coord", "Translator \(panel) error: \(msg)")
            failSession(TranslationError(message: msg, code: code))
        }
    }

    // MARK: - Chat turn building

    private func updateChatTurnFromInput(delta: String) {
        let now = Date()
        // Start a new turn after a silence gap. We deliberately do NOT split
        // on sentence terminators alone — continuous speech (e.g. a person
        // narrating a video) emits "…sentence one. sentence two…" without a
        // real pause, and per-sentence splitting fragments the UI into a
        // rapid-fire scroll of short bubbles.
        if openTurn == nil || shouldFinalizeTurn(now: now) {
            if let closing = openTurn {
                // Move the closed input turn into draining so its still-arriving
                // output deltas keep flowing into it instead of leaking into the
                // new openTurn. Only one draining slot exists — if a previous
                // draining turn is still here, promote it now (its output is
                // unlikely to keep coming after this much elapsed time).
                if let oldDraining = drainingTurn {
                    finalize(oldDraining)
                }
                drainingTurn = closing
                drainingTurnTranslatedFromPanel = openTurnTranslatedFromPanel
                drainingTurnLastOutputAt = now
            }
            openTurn = ChatTurn(
                startedAt: now,
                sourceLanguageCode: "auto",
                sourceText: delta,
                translatedLanguageCode: "",
                translatedText: ""
            )
            openTurnTranslatedFromPanel = nil
        } else {
            openTurn?.sourceText += delta
        }
        openTurnLastInputAt = now

        // Detect source language once we have a few characters; pick the
        // *other* configured language as the translation target.
        if let turn = openTurn,
           turn.sourceLanguageCode == "auto",
           turn.sourceText.unicodeScalars.count >= 4,
           let detected = detectLanguage(turn.sourceText) {
            openTurn?.sourceLanguageCode = detected
            let normalized = String(detected.split(separator: "-").first ?? Substring(detected))
            if normalized == primaryLanguageCode {
                openTurn?.translatedLanguageCode = secondaryLanguageCode
                openTurnTranslatedFromPanel = .secondary
            } else if normalized == secondaryLanguageCode {
                openTurn?.translatedLanguageCode = primaryLanguageCode
                openTurnTranslatedFromPanel = .primary
            } else {
                // Detected language isn't either configured language; default to
                // routing through the primary panel's translation.
                openTurn?.translatedLanguageCode = primaryLanguageCode
                openTurnTranslatedFromPanel = .primary
            }
        }
    }

    private func updateChatTurnFromOutput(delta: String, panel: Panel) {
        let now = Date()

        // Late deltas for the previous (draining) turn arrive here. Route them
        // to draining as long as its output stream is still active. Once the
        // gap exceeds drainingContinuityWindow we assume the previous turn's
        // translation is done — promote draining and let this delta fall
        // through to openTurn.
        if drainingTurn != nil, drainingTurnTranslatedFromPanel == panel {
            let stillStreaming = now.timeIntervalSince(drainingTurnLastOutputAt) < Self.drainingContinuityWindow
            if stillStreaming {
                drainingTurn?.translatedText += delta
                drainingTurnLastOutputAt = now
                return
            }
            // Output paused long enough — assume draining is done and promote.
            finalize(drainingTurn!)
            drainingTurn = nil
            drainingTurnTranslatedFromPanel = nil
            drainingTurnLastOutputAt = .distantPast
        }

        // Only route to openTurn once language detection has assigned a panel.
        guard openTurn != nil, let routePanel = openTurnTranslatedFromPanel,
              routePanel == panel else { return }
        openTurn?.translatedText += delta
    }

    private func shouldFinalizeTurn(now: Date) -> Bool {
        guard openTurn != nil else { return false }
        // Pause-only split. Threshold is generous enough that a speaker
        // pausing to breathe between sentences stays inside one turn,
        // but a real speaker change still gets its own row.
        return now.timeIntervalSince(openTurnLastInputAt) > 2.5
    }

    private func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        // Bias detection toward the two configured languages. The source is
        // almost always one of them, and unconstrained recognition misfires on
        // short input or script-sharing pairs (e.g. zh vs ja both using kanji).
        let candidates = Self.nlLanguages(for: primaryLanguageCode)
            + Self.nlLanguages(for: secondaryLanguageCode)
        if !candidates.isEmpty {
            recognizer.languageConstraints = candidates
            let weight = 1.0 / Double(candidates.count)
            recognizer.languageHints = Dictionary(candidates.map { ($0, weight) },
                                                  uniquingKeysWith: { first, _ in first })
        }
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Map one of our 13 base codes to the `NLLanguage` value(s) the recognizer
    /// reports, so detection constraints actually match its output.
    private static func nlLanguages(for code: String) -> [NLLanguage] {
        switch code {
        case "en": return [.english]
        case "zh": return [.simplifiedChinese, .traditionalChinese]
        case "es": return [.spanish]
        case "pt": return [.portuguese]
        case "fr": return [.french]
        case "de": return [.german]
        case "it": return [.italian]
        case "ja": return [.japanese]
        case "ko": return [.korean]
        case "ru": return [.russian]
        case "hi": return [.hindi]
        case "id": return [.indonesian]
        case "vi": return [.vietnamese]
        default: return []
        }
    }

    // MARK: - Refinement

    /// Move a finished turn into the chat log and kick off a best-effort
    /// context-aware refinement of its translation (see `TranslationRefiner`).
    private func finalize(_ turn: ChatTurn) {
        chatTurns.append(turn)
        persistDraft()
        scheduleRefinement(for: turn)
    }

    private func scheduleRefinement(for turn: ChatTurn) {
        guard settings.refineEnabled, networkCondition == .online else { return }
        let source = turn.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = turn.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !draft.isEmpty, !turn.translatedLanguageCode.isEmpty else { return }

        let apiKey = settings.apiKey
        guard !apiKey.isEmpty else { return }

        // Up to the last 3 finalized turns (excluding this one) for continuity.
        let context = chatTurns
            .filter { $0.id != turn.id && !$0.sourceText.isEmpty && !$0.bestTranslation.isEmpty }
            .suffix(3)
            .map { TranslationRefiner.ContextTurn(sourceText: $0.sourceText, translatedText: $0.bestTranslation) }

        let sourceName: String = {
            let code = turn.sourceLanguageCode
            guard !code.isEmpty, code != "auto" else { return "the source language" }
            return SupportedLanguages.englishName(forCode: code)
        }()

        let req = TranslationRefiner.Request(
            apiKey: apiKey,
            sourceText: turn.sourceText,
            draftTranslation: turn.translatedText,
            sourceLanguageEnglishName: sourceName,
            targetLanguageEnglishName: SupportedLanguages.englishName(forCode: turn.translatedLanguageCode),
            formalityClause: settings.formality.promptClause,
            glossary: settings.glossaryRules,
            recentContext: Array(context)
        )

        let turnID = turn.id
        let refiner = self.refiner
        Task { @MainActor [weak self] in
            let refined = await refiner.refine(req)
            guard let self, let refined else { return }
            // The turn may have been cleared (new conversation) or already
            // match the draft — only apply a genuine improvement.
            guard let idx = self.chatTurns.firstIndex(where: { $0.id == turnID }) else { return }
            if refined != self.chatTurns[idx].translatedText {
                self.chatTurns[idx].refinedText = refined
            }
        }
    }

    /// Append a delta to a per-panel buffer, grouping deltas into "lines" so the
    /// archive stays human-readable. A new line starts after a quiet gap;
    /// punctuation alone doesn't split, matching the chat-turn behavior.
    private func appendDelta(_ delta: String,
                             to lines: inout [TranscriptLine],
                             languageCode: String,
                             kind: TranscriptLine.Kind) {
        let now = Date()
        if var last = lines.last,
           now.timeIntervalSince(last.timestamp) < 2.5 {
            last.text += delta
            last.timestamp = now
            lines[lines.count - 1] = last
        } else {
            lines.append(TranscriptLine(
                timestamp: now,
                languageCode: languageCode,
                text: delta,
                kind: kind
            ))
        }
    }
}
