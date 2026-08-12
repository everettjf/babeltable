import Foundation
import Observation

/// In-app log buffer for diagnosing issues that don't surface in the UI —
/// WebSocket errors, OpenAI error payloads, audio failures, etc. The buffer
/// is shown in Settings → Diagnostics and can be copied/shared.
///
/// Logging from background threads is safe: call the nonisolated `diagLog(…)`
/// global, which captures a timestamp at the call site and hops to MainActor
/// to append. Each entry is also persisted to a JSON-line file in Documents
/// so logs survive a relaunch (handy when reproducing yesterday's hang).
@Observable
@MainActor
final class DiagnosticsLogger {
    static let shared = DiagnosticsLogger()

    nonisolated struct Entry: Identifiable, Codable, Sendable {
        var id: UUID = UUID()
        let timestamp: Date
        let level: Level
        let tag: String
        let message: String
    }

    nonisolated enum Level: String, Codable, Sendable, CaseIterable {
        case info
        case warn
        case error

        var label: String {
            switch self {
            case .info: return "INFO"
            case .warn: return "WARN"
            case .error: return "ERROR"
            }
        }
    }

    private(set) var entries: [Entry] = []

    private let maxEntries = 500
    /// Extra entries tolerated past `maxEntries` before trimming. Without
    /// slack, every entry past the cap would trigger a full-file rewrite.
    private let trimSlack = 50
    private let fileURL: URL
    private let writeQueue = DispatchQueue(label: "BabelTable.Diag.write", qos: .utility)

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("diagnostics.log")
        loadFromDisk()
    }

    // MARK: - Public

    func record(_ entry: Entry) {
        entries.append(entry)
        let didTrim = entries.count > maxEntries + trimSlack
        if didTrim {
            entries.removeFirst(entries.count - maxEntries)
        }

        let url = fileURL
        let snapshot = didTrim ? entries : nil
        writeQueue.async {
            if let snapshot {
                Self.rewrite(url: url, entries: snapshot)
            } else {
                Self.append(url: url, entry: entry)
            }
        }
    }

    func clear() {
        entries.removeAll()
        let url = fileURL
        writeQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Plain-text export suitable for copy/share.
    func exportText() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.map { e in
            "\(f.string(from: e.timestamp)) [\(e.level.label)] \(e.tag): \(e.message)"
        }.joined(separator: "\n")
    }

    // MARK: - Disk I/O

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(Entry.self, from: lineData) else { continue }
            loaded.append(entry)
        }
        if loaded.count > maxEntries {
            loaded.removeFirst(loaded.count - maxEntries)
        }
        entries = loaded
    }

    nonisolated private static func append(url: URL, entry: Entry) {
        guard let line = encode(entry) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { _ = try? handle.close() }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: line)
            }
        } else {
            try? line.write(to: url, options: [.atomic])
        }
    }

    nonisolated private static func rewrite(url: URL, entries: [Entry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var blob = Data()
        for entry in entries {
            guard let data = try? encoder.encode(entry) else { continue }
            blob.append(data)
            blob.append(0x0A)
        }
        try? blob.write(to: url, options: [.atomic])
    }

    nonisolated private static func encode(_ entry: Entry) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(entry) else { return nil }
        data.append(0x0A)
        return data
    }
}

/// Nonisolated logging entry point — safe to call from any thread, including
/// WebSocket receive loops and audio callbacks. Timestamp is captured at the
/// call site so ordering remains meaningful even though the actual append
/// hops to MainActor.
nonisolated func diagLog(_ level: DiagnosticsLogger.Level, tag: String, _ message: String) {
    let entry = DiagnosticsLogger.Entry(
        timestamp: Date(),
        level: level,
        tag: tag,
        message: message
    )
    Task { @MainActor in
        DiagnosticsLogger.shared.record(entry)
    }
}
