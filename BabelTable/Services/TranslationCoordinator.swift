import Foundation
import Observation
import UIKit

/// Owns one offline recognizer, explicit speaker direction, and durable local transcripts.
@Observable @MainActor
final class TranslationCoordinator {
    enum Status: Sendable, Equatable {
        case idle, starting, running, paused, stopping
        case error(TranslationError)
    }
    private(set) var status: Status = .idle
    private(set) var chatTurns: [ChatTurn] = []
    private(set) var openTurn: ChatTurn?
    private(set) var primaryLanguageCode = "en"
    private(set) var secondaryLanguageCode = "zh"
    private(set) var speakingPrimary = true
    private(set) var micLevel: Float = 0
    private(set) var sessionSummary: String?
    private(set) var saveFailure: String?
    private let settings: AppSettings
    private let store: SessionStore
    private let usage: UsageTracker
    private let audio: any AudioCapturing
    private let factory: @MainActor () -> any OfflineTranslating
    private let now: () -> Date
    private var translator: (any OfflineTranslating)?
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var watchdog: Task<Void, Never>?
    private var draftTask: Task<Void, Never>?
    private var startedAt: Date?
    private var sessionID: UUID?
    private var pendingSave: ChatSession?
    private var backgrounded = false

    init(settings: AppSettings, store: SessionStore, usage: UsageTracker,
         audio: (any AudioCapturing)? = nil,
         translatorFactory: @escaping @MainActor () -> any OfflineTranslating = { OfflineTranslator() },
         now: @escaping () -> Date = Date.init) {
        self.settings = settings; self.store = store; self.usage = usage
        self.audio = audio ?? AudioCaptureService(); self.factory = translatorFactory; self.now = now
        self.audio.onLevel = { [weak self] in self?.micLevel = $0 }
        self.audio.onInterruption = { [weak self] event in self?.handleInterruption(event) }
        self.audio.onMediaServicesReset = { [weak self] in
            guard let self, self.isSessionActive else { return }
            self.pause()
            self.resume()
        }
    }

    var isSessionActive: Bool { startedAt != nil && status != .idle }
    var hasUnsavedSession: Bool { pendingSave != nil }
    var hasContent: Bool { !chatTurns.isEmpty || openTurn != nil }
    var displayedPrimaryLanguage: Language {
        SupportedLanguages.resolve(hasContent || isSessionActive ? primaryLanguageCode : settings.primaryLanguageCode) ?? settings.primaryLanguage
    }
    var displayedSecondaryLanguage: Language {
        SupportedLanguages.resolve(hasContent || isSessionActive ? secondaryLanguageCode : settings.secondaryLanguageCode) ?? settings.secondaryLanguage
    }
    private var allTurns: [ChatTurn] { chatTurns + [openTurn].compactMap { $0 } }
    var primaryTranscript: String { panelText(primaryLanguageCode) }
    var secondaryTranscript: String { panelText(secondaryLanguageCode) }
    private func panelText(_ code: String) -> String {
        String(allTurns.filter { $0.translatedLanguageCode == code }.map(\.bestTranslation).joined(separator: "\n\n").suffix(4000))
    }
    var liveCaptionText: String {
        "BabelTable Live Captions\n\n" + allTurns.map { "\($0.sourceText)\n→ \($0.bestTranslation)" }.joined(separator: "\n\n")
    }

    func dismissError() { if case .error = status { status = .idle } }

    func start() async {
        dismissError()
        guard status == .idle, !hasUnsavedSession else { return }
        let pair = SessionLanguagePair(primary: settings.primaryLanguageCode, secondary: settings.secondaryLanguageCode)
        guard pair.primary != pair.secondary else {
            status = .error(TranslationError(raw: "Choose two different languages in Settings.")); return
        }
        chatTurns = []; openTurn = nil; sessionSummary = nil
        primaryLanguageCode = pair.primary; secondaryLanguageCode = pair.secondary
        speakingPrimary = true; backgrounded = false
        startedAt = now(); sessionID = UUID()
        status = .starting
        UIApplication.shared.isIdleTimerDisabled = true
        await beginRecognition()
    }

    private func beginRecognition() async {
        let token = UUID(); generation = token
        armWatchdog(token: token, seconds: 45)
        let source = speakingPrimary ? primaryLanguageCode : secondaryLanguageCode
        let target = speakingPrimary ? secondaryLanguageCode : primaryLanguageCode
        let engine = factory(); translator = engine
        engine.onEvent = { [weak self] event in
            guard let self, self.generation == token, self.startedAt != nil else { return }
            self.handle(event, source: source, target: target)
        }
        do {
            try await engine.start(source: source, target: target)
            guard generation == token, !Task.isCancelled, !backgrounded else { return }
            audio.onChunk = { [weak self] data in
                guard let self, self.generation == token, self.status == .running else { return }
                self.translator?.appendAudio(data)
            }
            try await audio.start(mode: settings.autoLevel == .on ? .voiceChat : .measurement)
            guard generation == token, !Task.isCancelled, !backgrounded else { return }
            watchdog?.cancel(); watchdog = nil
            status = .running
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            fail(error.localizedDescription)
        }
    }

    func selectSpeaker(primary: Bool) {
        guard status == .running, speakingPrimary != primary else { return }
        status = .starting
        audio.onChunk = nil; audio.stop(); micLevel = 0
        let token = generation
        let engine = translator
        armWatchdog(token: token, seconds: 20)
        operation = Task { @MainActor [weak self] in
            do {
                try await engine?.finish()
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.archiveOpenTurn()
                self.persistDraft()
                self.speakingPrimary = primary
                await self.beginRecognition()
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fail("The last utterance could not be completed. Your available text has been saved. Please start again.")
            }
        }
    }

    func stop() {
        guard startedAt != nil, status != .stopping else { return }
        // During preparation or a switch, cancel rather than concurrently finishing one engine twice.
        let shouldDrain = status == .running
        operation?.cancel(); operation = nil
        status = .stopping
        audio.onChunk = nil; audio.stop(); micLevel = 0
        let token = generation
        let engine = translator
        if !shouldDrain { finishSession(); status = .idle; return }
        armWatchdog(token: token, seconds: 20)
        operation = Task { @MainActor [weak self] in
            do {
                try await engine?.finish()
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.finishSession(); self.status = .idle
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fail("The final utterance could not be completed. Your available text has been saved.")
            }
        }
    }

    func newConversation() {
        guard !isSessionActive, !hasUnsavedSession else { return }
        chatTurns = []; openTurn = nil; sessionSummary = nil
    }

    func suspendForBackground() {
        guard startedAt != nil else { return }
        backgrounded = true
        if status == .stopping { finishSession(); status = .idle }
        else { pause() }
    }
    func resumeFromBackground() {
        guard backgrounded else { return }
        backgrounded = false; resume()
    }
    private func pause() {
        guard startedAt != nil else { return }
        cancelPipeline()
        archiveOpenTurn(); persistDraft()
        status = .paused
        UIApplication.shared.isIdleTimerDisabled = false
    }
    func resume() {
        guard status == .paused, !backgrounded else { return }
        status = .starting
        UIApplication.shared.isIdleTimerDisabled = true
        operation = Task { [weak self] in await self?.beginRecognition() }
    }
    private func handleInterruption(_ event: AudioCaptureService.InterruptionEvent) {
        guard startedAt != nil else { return }
        switch event {
        case .began: pause()
        case .resumed: resume()
        case .resumeFailed: fail("Microphone capture was interrupted. Check microphone access in device Settings and start again.")
        }
    }

    private func handle(_ event: OfflineEvent, source: String, target: String) {
        switch event {
        case .transcript(let id, let text, let final):
            if let idx = chatTurns.firstIndex(where: { $0.id == id }) {
                // Final speech results cannot be replaced by late volatile results.
                if final { chatTurns[idx].sourceText = text }
            } else {
                if openTurn?.id != id { archiveOpenTurn() }
                if openTurn == nil {
                    openTurn = ChatTurn(id: id, startedAt: now(), sourceLanguageCode: source,
                                        sourceText: text, translatedLanguageCode: target, translatedText: "")
                } else { openTurn?.sourceText = text }
                if final { archiveOpenTurn() }
            }
            scheduleDraft()
        case .translation(let id, let text):
            if let idx = chatTurns.firstIndex(where: { $0.id == id }) { chatTurns[idx].translatedText = text }
            else if openTurn?.id == id { openTurn?.translatedText = text }
            persistDraft()
        case .failure(let message): fail(message)
        }
    }
    private func archiveOpenTurn() {
        if let turn = openTurn, !turn.sourceText.isEmpty { chatTurns.append(turn) }
        openTurn = nil
    }
    private func armWatchdog(token: UUID, seconds: Int) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.generation == token else { return }
            self.fail("The local speech engine took too long to respond. Your available text has been saved. Try starting again.")
        }
    }
    private func cancelPipeline() {
        watchdog?.cancel(); watchdog = nil
        generation = UUID()
        operation?.cancel(); operation = nil
        audio.onChunk = nil; audio.stop(); micLevel = 0
        translator?.cancel(); translator = nil
    }
    private func fail(_ message: String) {
        finishSession(); status = .error(TranslationError(raw: message))
    }
    private func finishSession() {
        cancelPipeline()
        draftTask?.cancel(); draftTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
        archiveOpenTurn()
        if let startedAt {
            usage.recordSession(durationSeconds: max(0, now().timeIntervalSince(startedAt)))
            if hasContent, let session = snapshot(endedAt: now()) {
                if store.save(session) { saveFailure = nil; pendingSave = nil; sessionSummary = "Conversation saved on this device" }
                else { pendingSave = session; reportSaveFailure() }
            }
        }
        startedAt = nil; sessionID = nil
    }
    private func snapshot(endedAt: Date?) -> ChatSession? {
        guard let startedAt, let sessionID else { return nil }
        let lines = allTurns.filter { !$0.bestTranslation.isEmpty }.map {
            TranscriptLine(id: $0.id, timestamp: $0.startedAt, languageCode: $0.translatedLanguageCode,
                           text: $0.bestTranslation, kind: .output)
        }
        return ChatSession(id: sessionID, startedAt: startedAt, endedAt: endedAt,
                           primaryLanguageCode: primaryLanguageCode, secondaryLanguageCode: secondaryLanguageCode,
                           primaryLines: lines.filter { $0.languageCode == primaryLanguageCode },
                           secondaryLines: lines.filter { $0.languageCode == secondaryLanguageCode }, chatTurns: allTurns)
    }
    private func persistDraft() {
        draftTask?.cancel(); draftTask = nil
        guard hasContent, let session = snapshot(endedAt: nil) else { return }
        if store.save(session) { saveFailure = nil } else { reportSaveFailure() }
    }
    private func scheduleDraft() {
        guard draftTask == nil else { return }
        draftTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self?.persistDraft()
        }
    }
    private func reportSaveFailure() {
        sessionSummary = nil
        saveFailure = "Could not save this conversation. Keep the app open, free some storage, then retry. You can also share the text now."
    }
    func retrySave() {
        if let pendingSave {
            guard store.save(pendingSave) else { reportSaveFailure(); return }
            self.pendingSave = nil; saveFailure = nil; sessionSummary = "Conversation saved on this device"
        } else { persistDraft() }
    }
}
