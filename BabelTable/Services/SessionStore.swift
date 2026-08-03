import Foundation
import Observation

/// Persists archived chat sessions as JSON files in the app's Documents directory.
@Observable
@MainActor
final class SessionStore {
    private(set) var sessions: [ChatSession] = []

    private let folderURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init() {
        reload()
    }

    func reload() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            sessions = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [ChatSession] = []
        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let s = try? decoder.decode(ChatSession.self, from: data) {
                loaded.append(s)
            }
        }
        sessions = loaded.sorted { $0.startedAt > $1.startedAt }
    }

    func save(_ session: ChatSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        let url = folderURL.appendingPathComponent("\(session.id.uuidString).json")
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: url, options: [.atomic])
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    func delete(_ session: ChatSession) {
        let url = folderURL.appendingPathComponent("\(session.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        sessions.removeAll { $0.id == session.id }
    }
}
