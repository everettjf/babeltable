import Foundation
import NaturalLanguage
import Observation

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
    }

    func start() async {
        // A previous error should not block restarting.
        if case .error = status { status = .idle }
        guard status != .running, status != .starting else { return }

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
        sessionStartedAt = Date()
        primaryLanguageCode = settings.primaryLanguageCode
        secondaryLanguageCode = settings.secondaryLanguageCode

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
            status = .error(TranslationError(raw: error.localizedDescription))
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
        // A reconnect is already queued — ignore follow-on errors from the
        // dying socket until that attempt resolves.
        guard !awaitingReconnect else { return }

        if error.isRecoverable, reconnectAttempts < Self.maxReconnectAttempts {
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

    /// Stop audio, close sockets, finalize pending turns, record usage, and
    /// persist the session. Shared by a clean stop and a fatal error.
    private func finishSession() {
        reconnectTask?.cancel()
        reconnectTask = nil
        awaitingReconnect = false
        reconnectAttempts = 0
        audio.stop()
        tearDownConnections()

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
        if let startedAt = sessionStartedAt {
            let elapsed = Date().timeIntervalSince(startedAt)
            usage.recordSession(durationSeconds: elapsed)
        }

        // Persist the session if there is anything to save.
        if let startedAt = sessionStartedAt,
           !primaryLines.isEmpty || !secondaryLines.isEmpty || !inputLines.isEmpty || !chatTurns.isEmpty {
            let session = ChatSession(
                startedAt: startedAt,
                endedAt: Date(),
                primaryLanguageCode: primaryLanguageCode,
                secondaryLanguageCode: secondaryLanguageCode,
                primaryLines: primaryLines,
                secondaryLines: secondaryLines,
                chatTurns: chatTurns
            )
            store.save(session)
        }

        sessionStartedAt = nil
    }

    // MARK: - Private

    private enum Panel { case primary, secondary }

    /// Build both target-language sockets, wire mic fan-out, and connect.
    /// Used both on a fresh start and on reconnect; relies on
    /// `primaryLanguageCode`/`secondaryLanguageCode` already being set.
    private func buildAndConnectTranslators() {
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

    private func handle(event: RealtimeTranslator.Event, panel: Panel) {
        switch event {
        case .state(let s):
            switch s {
            case .ready:
                // A socket came up. If we were reconnecting, we're live again.
                if status == .reconnecting {
                    diagLog(.info, tag: "Coord", "Reconnected (\(panel))")
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
            appendDelta(delta, to: &inputLines, languageCode: "auto", kind: .input)
            updateChatTurnFromInput(delta: delta)
        case .outputDelta(let delta):
            switch panel {
            case .primary:
                primaryTranscript += delta
                appendDelta(delta, to: &primaryLines, languageCode: primaryLanguageCode, kind: .output)
            case .secondary:
                secondaryTranscript += delta
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
        scheduleRefinement(for: turn)
    }

    private func scheduleRefinement(for turn: ChatTurn) {
        guard settings.refineEnabled else { return }
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
