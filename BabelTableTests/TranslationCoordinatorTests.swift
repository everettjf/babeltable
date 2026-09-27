import XCTest
@testable import BabelTable

@MainActor
final class TranslationCoordinatorTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var settings: AppSettings!
    private var store: SessionStore!
    private var audio: TestAudio!
    private var coordinator: TranslationCoordinator!
    private var engines: [TestTranslator] = []
    private var startError: Error?

    override func setUpWithError() throws {
        suite = "BabelTableTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        settings = AppSettings(defaults: defaults)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        store = SessionStore(folderURL: directory)
        audio = TestAudio()
        coordinator = TranslationCoordinator(settings: settings, store: store,
            usage: UsageTracker(fileURL: directory.appendingPathComponent("usage.data")), audio: audio,
            translatorFactory: { [unowned self] in
                let engine = TestTranslator()
                engine.startError = self.startError
                self.engines.append(engine)
                return engine
            })
    }

    override func tearDownWithError() throws {
        coordinator.suspendForBackground()
        coordinator.stop()
        audio.resumePending()
        engines.forEach { $0.resumeFinish() }
        coordinator = nil
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
        engines = []
    }
    private func settle() async { for _ in 0..<40 { await Task.yield() } }
    private func speak(_ text: String = "Hello", final: Bool = true, id: UUID = UUID()) -> UUID {
        engines.last!.emit(.transcript(id: id, text: text, isFinal: final)); return id
    }

    func testStartsWithoutAccountConsentOrNetworkDependency() async {
        await coordinator.start()
        XCTAssertEqual(coordinator.status, .running)
        XCTAssertEqual(engines.count, 1)
        XCTAssertEqual(engines[0].source, "en")
        XCTAssertEqual(engines[0].target, "zh")
        audio.onChunk?(Data([0, 0]))
        XCTAssertEqual(engines[0].chunks, 1)
    }
    func testMissingModelsBlocksMicrophone() async {
        startError = OfflineError.modelsMissing
        await coordinator.start()
        XCTAssertEqual(audio.starts, 0)
        if case .error(let error) = coordinator.status { XCTAssertTrue(error.message.contains("Download")) }
        else { XCTFail("Missing assets must be actionable") }
    }
    func testSameLanguagesBlockedBeforeEngineCreation() async {
        settings.secondaryLanguageCode = "en"
        await coordinator.start()
        XCTAssertTrue(engines.isEmpty)
        XCTAssertEqual(audio.starts, 0)
    }
    func testStopDuringPendingPermissionCannotRestartCapture() async {
        audio.holdStart = true
        let starting = Task { await coordinator.start() }
        await settle()
        coordinator.stop()
        audio.resumePending()
        await starting.value
        XCTAssertEqual(coordinator.status, .idle)
        XCTAssertFalse(coordinator.isSessionActive)
        XCTAssertNil(audio.onChunk)
    }
    func testVolatileResultsReplaceInsteadOfDuplicating() async {
        await coordinator.start()
        let id = speak("Hel", final: false)
        _ = speak("Hello", final: false, id: id)
        XCTAssertEqual(coordinator.openTurn?.sourceText, "Hello")
        _ = speak("Hello!", id: id)
        _ = speak("late partial", final: false, id: id)
        XCTAssertEqual(coordinator.chatTurns.count, 1)
        XCTAssertNil(coordinator.openTurn)
        XCTAssertEqual(coordinator.chatTurns[0].sourceText, "Hello!")
    }
    func testTranslationsAreOwnedByUtteranceID() async {
        await coordinator.start()
        let first = speak("First")
        let second = speak("Second")
        engines[0].emit(.translation(id: second, text: "第二"))
        engines[0].emit(.translation(id: first, text: "第一"))
        XCTAssertEqual(coordinator.chatTurns.map(\.translatedText), ["第一", "第二"])
        XCTAssertEqual(store.sessions.first?.chatTurns?.map(\.translatedText), ["第一", "第二"])
    }
    func testStopWaitsForFinalResultAndSavesOneSession() async {
        await coordinator.start()
        let id = speak("Hello", final: false)
        engines[0].holdFinish = true
        coordinator.stop()
        await settle()
        XCTAssertEqual(coordinator.status, .stopping)
        _ = speak("Hello world", id: id)
        engines[0].emit(.translation(id: id, text: "你好世界"))
        engines[0].resumeFinish()
        await settle()
        XCTAssertEqual(coordinator.status, .idle)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertNotNil(store.sessions[0].endedAt)
        XCTAssertEqual(store.sessions[0].chatTurns?.first?.translatedText, "你好世界")
    }
    func testSwitchDrainsOldDirectionBeforeStartingReverse() async {
        await coordinator.start()
        let id = speak()
        engines[0].holdFinish = true
        coordinator.selectSpeaker(primary: false)
        await settle()
        XCTAssertEqual(engines.count, 1)
        engines[0].emit(.translation(id: id, text: "你好"))
        engines[0].resumeFinish()
        await settle()
        XCTAssertEqual(coordinator.status, .running)
        XCTAssertEqual(engines.count, 2)
        XCTAssertEqual(engines[1].source, "zh")
        XCTAssertEqual(engines[1].target, "en")
        XCTAssertEqual(coordinator.chatTurns.first?.translatedLanguageCode, "zh")
        _ = speak("谢谢")
        XCTAssertEqual(coordinator.chatTurns.last?.translatedLanguageCode, "en")
    }
    func testOldEngineCannotChangeNewDirection() async {
        await coordinator.start()
        let old = engines[0]
        coordinator.selectSpeaker(primary: false)
        await settle()
        old.emit(.transcript(id: UUID(), text: "stale", isFinal: true))
        old.emit(.failure("stale error"))
        XCTAssertTrue(coordinator.chatTurns.isEmpty)
        XCTAssertEqual(coordinator.status, .running)
    }
    func testBackgroundSavesPartialAndResumeKeepsSessionID() async {
        await coordinator.start()
        _ = speak("Partial", final: false)
        coordinator.suspendForBackground()
        let id = store.sessions.first?.id
        XCTAssertEqual(coordinator.status, .paused)
        XCTAssertEqual(store.sessions.first?.chatTurns?.first?.sourceText, "Partial")
        coordinator.resumeFromBackground()
        await settle()
        _ = speak("Next")
        coordinator.stop()
        await settle()
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.id, id)
        XCTAssertEqual(store.sessions.first?.chatTurns?.count, 2)
    }
    func testInterruptionDoesNotCaptureUntilResume() async {
        await coordinator.start()
        audio.onInterruption?(.began)
        XCTAssertEqual(coordinator.status, .paused)
        XCTAssertNil(audio.onChunk)
        audio.onInterruption?(.resumed)
        await settle()
        XCTAssertEqual(coordinator.status, .running)
        XCTAssertEqual(engines.count, 2)
    }
    func testStopDuringSwitchDoesNotStartAnotherEngine() async {
        await coordinator.start()
        engines[0].holdFinish = true
        coordinator.selectSpeaker(primary: false)
        await settle()
        coordinator.stop()
        engines[0].resumeFinish()
        await settle()
        XCTAssertEqual(coordinator.status, .idle)
        XCTAssertEqual(engines.count, 1)
    }
    func testSettingsChangesDoNotChangeActiveLanguagePair() async {
        await coordinator.start()
        settings.primaryLanguageCode = "fr"
        settings.secondaryLanguageCode = "ja"
        coordinator.selectSpeaker(primary: false)
        await settle()
        XCTAssertEqual(engines.last?.source, "zh")
        XCTAssertEqual(engines.last?.target, "en")
    }
    func testFailedSaveRetainsTranscriptAndRetryReusesID() async throws {
        await coordinator.start()
        _ = speak()
        try FileManager.default.removeItem(at: directory)
        try Data([1]).write(to: directory)
        coordinator.stop()
        await settle()
        XCTAssertTrue(coordinator.hasUnsavedSession)
        XCTAssertNotNil(coordinator.saveFailure)
        coordinator.newConversation()
        XCTAssertFalse(coordinator.chatTurns.isEmpty)
        try FileManager.default.removeItem(at: directory)
        coordinator.retrySave()
        XCTAssertFalse(coordinator.hasUnsavedSession)
        XCTAssertEqual(store.sessions.count, 1)
    }
}

@MainActor
private final class TestTranslator: OfflineTranslating {
    var onEvent: (@MainActor @Sendable (OfflineEvent) -> Void)?
    var startError: Error?
    var source = "", target = ""
    var chunks = 0
    var holdFinish = false
    private var pending: CheckedContinuation<Void, Never>?
    func start(source: String, target: String) async throws {
        if let startError { throw startError }
        self.source = source; self.target = target
    }
    func appendAudio(_ data: Data) { chunks += 1 }
    func finish() async throws {
        if holdFinish { await withCheckedContinuation { pending = $0 } }
    }
    func cancel() {}
    func emit(_ event: OfflineEvent) { onEvent?(event) }
    func resumeFinish() { pending?.resume(); pending = nil }
}

@MainActor
private final class TestAudio: AudioCapturing {
    var onChunk: (@MainActor @Sendable (Data) -> Void)?
    var onLevel: (@MainActor @Sendable (Float) -> Void)?
    var onInterruption: (@MainActor @Sendable (AudioCaptureService.InterruptionEvent) -> Void)?
    var onMediaServicesReset: (@MainActor @Sendable () -> Void)?
    var starts = 0
    var holdStart = false
    private var pending: CheckedContinuation<Void, Never>?
    func start(mode: AudioCaptureService.CaptureMode) async throws {
        starts += 1
        if holdStart { await withCheckedContinuation { pending = $0 } }
    }
    func restart() async throws { try await start(mode: .measurement) }
    func stop() {}
    func resumePending() { pending?.resume(); pending = nil }
}
