import Foundation
import XCTest
@testable import BabelTable

@MainActor
final class SessionStoreTests: XCTestCase {
    private var folderURL: URL!

    override func setUpWithError() throws {
        folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BabelTable-SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let folderURL, FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        }
        folderURL = nil
    }

    func testSaveAndReloadPreservesCompleteSession() throws {
        let session = makeSession()
        SessionStore(folderURL: folderURL).save(session)

        let reloaded = SessionStore(folderURL: folderURL)

        XCTAssertEqual(reloaded.sessions, [session])
    }

    func testFinalSessionOverwritesDraftWithoutDuplication() throws {
        let store = SessionStore(folderURL: folderURL)
        let draft = makeSession(endedAt: nil)
        var final = draft
        final.endedAt = draft.startedAt.addingTimeInterval(90)
        final.chatTurns?.append(makeTurn(offset: 30, source: "Goodbye", translation: "再见"))

        store.save(draft)
        store.save(final)

        XCTAssertEqual(store.sessions, [final])
        XCTAssertEqual(try jsonFiles().count, 1)
        XCTAssertEqual(SessionStore(folderURL: folderURL).sessions, [final])
    }

    func testRepeatedSaveKeepsSingleSession() throws {
        let store = SessionStore(folderURL: folderURL)
        let session = makeSession()

        store.save(session)
        store.save(session)
        store.save(session)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(try jsonFiles().count, 1)
    }

    func testDeleteRemovesMemoryAndFilePermanently() throws {
        let store = SessionStore(folderURL: folderURL)
        let session = makeSession()
        store.save(session)

        store.delete(session)

        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertTrue(try jsonFiles().isEmpty)
        XCTAssertTrue(SessionStore(folderURL: folderURL).sessions.isEmpty)
    }

    func testOlderArchiveWithoutOptionalFieldsStillLoads() throws {
        let session = makeSession()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(session)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var turns = try XCTUnwrap(json["chatTurns"] as? [[String: Any]])
        turns[0].removeValue(forKey: "refinedText")
        json["chatTurns"] = turns
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        try legacyData.write(to: fileURL(for: session.id), options: .atomic)

        let loaded = try XCTUnwrap(SessionStore(folderURL: folderURL).sessions.first)

        XCTAssertEqual(loaded.id, session.id)
        XCTAssertNil(try XCTUnwrap(loaded.chatTurns).first?.refinedText)
    }

    func testArchiveWithoutChatTurnsStillLoads() throws {
        let session = makeSession()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(session)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "chatTurns")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        try legacyData.write(to: fileURL(for: session.id), options: .atomic)

        let loaded = try XCTUnwrap(SessionStore(folderURL: folderURL).sessions.first)

        XCTAssertEqual(loaded.id, session.id)
        XCTAssertNil(loaded.chatTurns)
    }

    func testCorruptArchiveDoesNotHideValidSessions() throws {
        let valid = makeSession()
        SessionStore(folderURL: folderURL).save(valid)
        try Data("not valid json".utf8)
            .write(to: folderURL.appendingPathComponent("corrupt.json"), options: .atomic)

        let reloaded = SessionStore(folderURL: folderURL)

        XCTAssertEqual(reloaded.sessions, [valid])
    }

    private func makeSession(endedAt: Date? = Date(timeIntervalSince1970: 1_700_000_120)) -> ChatSession {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let turn = makeTurn(offset: 5, source: "Hello", translation: "你好")
        return ChatSession(
            id: UUID(uuidString: "9FCE40E7-3B75-4EF8-A120-F9AFBFBC7E37")!,
            startedAt: startedAt,
            endedAt: endedAt,
            primaryLanguageCode: "en",
            secondaryLanguageCode: "zh",
            primaryLines: [
                TranscriptLine(
                    id: UUID(uuidString: "42403073-C720-4D6C-A9E6-1611750EAEE7")!,
                    timestamp: turn.startedAt,
                    languageCode: "en",
                    text: turn.sourceText,
                    kind: .input
                )
            ],
            secondaryLines: [
                TranscriptLine(
                    id: UUID(uuidString: "2B4195C7-2CC6-4439-88EA-19F2CA5CC99A")!,
                    timestamp: turn.startedAt,
                    languageCode: "zh",
                    text: turn.bestTranslation,
                    kind: .output
                )
            ],
            chatTurns: [turn]
        )
    }

    private func makeTurn(offset: TimeInterval, source: String, translation: String) -> ChatTurn {
        ChatTurn(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            sourceLanguageCode: "en",
            sourceText: source,
            translatedLanguageCode: "zh",
            translatedText: translation,
            refinedText: "\(translation)！"
        )
    }

    private func fileURL(for id: UUID) -> URL {
        folderURL.appendingPathComponent("\(id.uuidString).json")
    }

    private func jsonFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
    }
}
