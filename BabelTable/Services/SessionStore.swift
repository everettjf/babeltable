import Foundation
import Observation

/// Persists archived chat sessions as JSON files in the app's Documents directory.
@Observable
@MainActor
final class SessionStore {
    private(set) var sessions: [ChatSession] = []

    private let folderURL: URL

    private static func defaultFolderURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Sessions", isDirectory: true)
    }

    /// `folderURL` is injectable so persistence can be verified against an
    /// isolated temporary directory without touching the user's real archive.
    init(folderURL: URL? = nil) {
        self.folderURL = folderURL ?? Self.defaultFolderURL()
        try? FileManager.default.createDirectory(
            at: self.folderURL,
            withIntermediateDirectories: true
        )
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
        do {
            let data = try encoder.encode(session)
            try data.write(to: url, options: [.atomic])
        } catch {
            // A silently lost session is the worst failure mode for an
            // archive — at least surface it in the diagnostics log.
            diagLog(.error, tag: "Store", "Failed to save session \(session.id.uuidString): \(error.localizedDescription)")
            return
        }
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    func delete(_ session: ChatSession) {
        let url = folderURL.appendingPathComponent("\(session.id.uuidString).json")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            diagLog(.error, tag: "Store", "Failed to delete session \(session.id.uuidString): \(error.localizedDescription)")
            return
        }
        sessions.removeAll { $0.id == session.id }
    }
}
