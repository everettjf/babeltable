import XCTest
@testable import BabelTable

@MainActor
final class TranslationCoordinatorTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var keychain: KeychainStore!
    private var settings: AppSettings!
    private var store: SessionStore!
    private var audio: TestAudio!
    private var coordinator: TranslationCoordinator!
    private var sockets: [TestConnection] = []
    private var date = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        suite = "BabelTableTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        keychain = KeychainStore(service: suite)
        settings = AppSettings(defaults: defaults, keychain: keychain)
        try settings.saveAPIKey("test-only-placeholder")
        settings.aiConsentVersion = AppSettings.currentConsentVersion
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        store = SessionStore(folderURL: directory)
        audio = TestAudio()
        coordinator = TranslationCoordinator(settings: settings, store: store,
            usage: UsageTracker(fileURL: directory.appendingPathComponent("usage.data")), audio: audio,
            connectionFactory: { [unowned self] _, _, _, callback in
                let connection = TestConnection(callback)
                self.sockets.append(connection)
                return connection
            }, monitorConnectivity: false, now: { [unowned self] in self.date },
            refine: { _ in "Refined translation" })
    }

    override func tearDownWithError() throws {
        coordinator.stop()
        audio.resumePending()
        coordinator = nil
        try keychain.deleteAPIKey()
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        sockets = []
    }

    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    private func startLive() async {
        await coordinator.start()
        sockets.suffix(2).forEach { $0.emit(.state(.ready)) }
        await settle()
        XCTAssertEqual(coordinator.status, .running)
    }

    func testBothConnectionsAndMicrophoneMustBeReadyBeforeAudioIsSent() async {
        await coordinator.start()
        XCTAssertEqual(coordinator.status, .starting)
        sockets[0].emit(.state(.ready))
        audio.onChunk?(Data([0, 0]))
        await settle()
        XCTAssertEqual(coordinator.status, .starting)
        XCTAssertEqual(sockets[0].chunks, 0)
        sockets[1].emit(.state(.ready))
        await settle()
        XCTAssertEqual(coordinator.status, .running)
        audio.onChunk?(Data([0, 0]))
        await settle()
        XCTAssertEqual(sockets.map(\.chunks), [1, 1])
    }

    func testConsentBlocksAllCaptureAndConnections() async {
        settings.aiConsentVersion = 0
        await coordinator.start()
        XCTAssertTrue(sockets.isEmpty)
        XCTAssertEqual(audio.starts, 0)
    }

    func testStopWhilePermissionPendingDoesNotResumeSession() async {
        audio.holdStart = true
        let starting = Task { await coordinator.start() }
        await settle()
        XCTAssertEqual(coordinator.status, .starting)
        coordinator.stop()
        audio.resumePending()
        await starting.value
        XCTAssertEqual(coordinator.status, .idle)
        sockets.forEach { $0.emit(.state(.ready)) }
        await settle()
        XCTAssertEqual(coordinator.status, .idle)
    }

    func testOldSocketCannotMutateNewSession() async {
        await startLive()
        let old = sockets[0]
        coordinator.stop()
        await startLive()
        old.emit(.inputDelta("stale transcript"))
        old.emit(.error(message: "invalid key", code: "invalid_api_key"))
        await settle()
        XCTAssertEqual(coordinator.status, .running)
        XCTAssertNil(coordinator.openTurn)
        XCTAssertTrue(coordinator.primaryTranscript.isEmpty)
    }

    func testShortChineseUtteranceKeepsOutputThatArrivedFirst() async throws {
        await startLive()
        sockets[0].emit(.outputDelta("Hello"))
        await settle()
        sockets[0].emit(.inputDelta("你好"))
        await settle()
        XCTAssertEqual(coordinator.openTurn?.translatedText, "Hello")
        coordinator.stop()
        let session = try XCTUnwrap(SessionStore(folderURL: directory).sessions.first)
        XCTAssertEqual(session.chatTurns?.first?.sourceText, "你好")
        XCTAssertEqual(session.chatTurns?.first?.translatedText, "Hello")
    }

    func testShortEnglishUtteranceReceivesWholeTranslation() async {
        await startLive()
        sockets[0].emit(.inputDelta("Hi"))
        await settle()
        sockets[1].emit(.outputDelta("你好"))
        await settle()
        XCTAssertEqual(coordinator.openTurn?.translatedText, "你好")
    }

    func testBackgroundDraftIncludesOpenAndDrainingTurnsWithoutDuplicates() async throws {
        await startLive()
        sockets[0].emit(.inputDelta("Hello there"))
        await settle()
        sockets[1].emit(.outputDelta("你好"))
        await settle()
        date += 3
        sockets[0].emit(.inputDelta("谢谢"))
        await settle()
        sockets[0].emit(.outputDelta("Thank you"))
        await settle()
        coordinator.suspendForBackground()
        let draft = try XCTUnwrap(SessionStore(folderURL: directory).sessions.first)
        XCTAssertEqual(draft.chatTurns?.map(\.sourceText), ["Hello there", "谢谢"])
        XCTAssertEqual(draft.chatTurns?.map(\.translatedText), ["你好", "Thank you"])
        XCTAssertNil(draft.endedAt)
        coordinator.stop()
        let final = try XCTUnwrap(SessionStore(folderURL: directory).sessions.first)
        XCTAssertEqual(final.id, draft.id)
        XCTAssertEqual(final.chatTurns?.count, 2)
        XCTAssertNotNil(final.endedAt)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testSaveFailureIsVisibleAndBlocksClearingUntilRetry() async throws {
        await startLive()
        sockets[0].emit(.inputDelta("Keep this conversation"))
        await settle()
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory) // A file cannot hold session files.
        coordinator.stop()
        XCTAssertNotNil(coordinator.saveFailure)
        XCTAssertNil(coordinator.sessionSummary)
        XCTAssertTrue(coordinator.hasUnsavedSession)
        coordinator.newConversation()
        await coordinator.start()
        XCTAssertTrue(coordinator.hasContent)
        XCTAssertEqual(sockets.count, 2)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        coordinator.retrySave()
        XCTAssertNil(coordinator.saveFailure)
        XCTAssertFalse(coordinator.hasUnsavedSession)
        XCTAssertNotNil(coordinator.sessionSummary)
        XCTAssertEqual(SessionStore(folderURL: directory).sessions.first?.chatTurns?.first?.sourceText, "Keep this conversation")
    }

    func testOfflineForegroundWaitsForConnectivityAndKeepsSameArchive() async {
        await startLive()
        sockets[0].emit(.inputDelta("Hello"))
        await settle()
        coordinator.suspendForBackground()
        coordinator.handleConnectivity(.offline)
        coordinator.resumeFromBackground()
        XCTAssertEqual(sockets.count, 2)
        coordinator.handleConnectivity(.online)
        await settle()
        XCTAssertEqual(sockets.count, 4)
        sockets[2].emit(.state(.ready))
        sockets[3].emit(.state(.ready))
        await settle()
        XCTAssertEqual(coordinator.status, .running)
        coordinator.stop()
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testInterruptionAndSocketReadinessCannotReportLiveWithPausedMic() async {
        await startLive()
        audio.onInterruption?(.began)
        await settle()
        sockets[0].emit(.state(.ready))
        sockets[1].emit(.state(.ready))
        await settle()
        XCTAssertEqual(coordinator.status, .reconnecting)
        audio.onInterruption?(.resumed)
        await settle()
        XCTAssertEqual(coordinator.status, .running)
    }

    func testMicrophoneFailureDuringNetworkBackoffIsNotIgnored() async {
        await startLive()
        sockets[0].emit(.error(message: "Connection lost", code: nil))
        await settle()
        XCTAssertEqual(coordinator.status, .reconnecting)
        audio.onInterruption?(.resumeFailed("System declined audio resume"))
        if case .error(let error) = coordinator.status { XCTAssertEqual(error.kind, .microphone) }
        else { XCTFail("A failed microphone must end the session even during network backoff") }
    }

    func testLanguageLabelsStayWithVisibleSession() async {
        await startLive()
        settings.primaryLanguageCode = "ja"
        XCTAssertEqual(coordinator.displayedPrimaryLanguage.code, "en")
        sockets[0].emit(.inputDelta("Hello"))
        await settle()
        coordinator.stop()
        XCTAssertEqual(coordinator.displayedPrimaryLanguage.code, "en")
        coordinator.newConversation()
        XCTAssertEqual(coordinator.displayedPrimaryLanguage.code, "ja")
    }

    func testRapidLanguageChangeStartsAnotherTurn() async {
        await startLive()
        sockets[0].emit(.inputDelta("Hello there"))
        await settle()
        sockets[1].emit(.outputDelta("你好"))
        await settle()
        date += 0.2
        sockets[0].emit(.inputDelta("谢谢"))
        await settle()
        sockets[0].emit(.outputDelta("Thank you"))
        await settle()
        coordinator.stop()
        XCTAssertEqual(store.sessions.first?.chatTurns?.map(\.sourceText), ["Hello there", "谢谢"])
        XCTAssertEqual(store.sessions.first?.chatTurns?.map(\.translatedText), ["你好", "Thank you"])
    }

    func testMediaResetCannotRestartCaptureAfterStop() async {
        await startLive()
        audio.onMediaServicesReset?()
        await settle()
        coordinator.stop()
        let count = audio.starts
        sockets.suffix(2).forEach { $0.emit(.state(.ready)) }
        await settle()
        XCTAssertEqual(coordinator.status, .idle)
        XCTAssertEqual(audio.starts, count)
    }

    func testSameLanguagesCannotOpenBillableConnections() async {
        settings.secondaryLanguageCode = settings.primaryLanguageCode
        await coordinator.start()
        XCTAssertTrue(sockets.isEmpty)
        XCTAssertEqual(audio.starts, 0)
    }

    func testRefinementUpdatesThePersistedDraft() async throws {
        settings.refineEnabled = true
        await startLive()
        sockets[0].emit(.inputDelta("Hello there"))
        await settle()
        sockets[1].emit(.outputDelta("你好"))
        await settle()
        date += 3
        sockets[0].emit(.inputDelta("Thank you"))
        await settle()
        date += 3
        sockets[0].emit(.inputDelta("Goodbye"))
        await settle()
        XCTAssertEqual(coordinator.chatTurns.first?.refinedText, "Refined translation")
        let saved = try XCTUnwrap(SessionStore(folderURL: directory).sessions.first)
        XCTAssertEqual(saved.chatTurns?.first?.refinedText, "Refined translation")
        coordinator.stop()
        let final = try XCTUnwrap(SessionStore(folderURL: directory).sessions.first)
        XCTAssertEqual(final.chatTurns?.first?.bestTranslation, coordinator.chatTurns.first?.bestTranslation)
    }

    func testRemoteErrorsNeverEnterDiagnosticSummary() {
        let remoteText = "sk-test-private-key and confidential transcript"
        let code = RealtimeTranslator.safeErrorCode(remoteText, message: remoteText)
        XCTAssertEqual(code, "service_error")
        XCTAssertEqual(RealtimeTranslator.safeErrorCode("insufficient_quota", message: remoteText), "insufficient_quota")
    }

    func testTextExportIsARealUTF8File() throws {
        let text = "你好 👋\nHello\nありがとうございます"
        let url = try ConversationExport(text: text).writeFile()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "txt")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
    }

    func testFreshDefaultsDisableRefinementAndKeyCanBeDeleted() throws {
        XCTAssertFalse(settings.refineEnabled)
        try settings.deleteAPIKey()
        XCTAssertFalse(settings.hasAPIKey)
        XCTAssertTrue(settings.apiKey.isEmpty)
    }
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
    func restart() async throws { try await start(mode: .voiceChat) }
    func stop() {}
    func resumePending() { pending?.resume(); pending = nil }
}

nonisolated private final class TestConnection: RealtimeConnection, @unchecked Sendable {
    let callback: @Sendable (RealtimeTranslator.Event) -> Void
    var chunks = 0
    init(_ callback: @escaping @Sendable (RealtimeTranslator.Event) -> Void) { self.callback = callback }
    func connect() {}
    func close() {}
    func appendAudio(_ data: Data) { chunks += 1 }
    func emit(_ event: RealtimeTranslator.Event) { callback(event) }
}
