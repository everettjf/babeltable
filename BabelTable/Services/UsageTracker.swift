import Foundation
import Observation

/// Records how many minutes of microphone audio have been streamed through
/// the translation API per day, and computes an estimated USD cost.
///
/// `gpt-realtime-translate` is billed at $0.034 per minute of audio per
/// session; we run two parallel sessions (one per target language) so the
/// effective rate is `pricePerMinute * parallelSessions`.
@Observable
@MainActor
final class UsageTracker {
    static let pricePerMinutePerSession: Double = 0.034
    static let parallelSessions: Int = 2

    /// Per-minute cost for a typical BabelTable conversation (USD).
    static var pricePerMinute: Double {
        pricePerMinutePerSession * Double(parallelSessions)
    }

    private(set) var entries: [DailyUsage] = []

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("usage.json")
    }()

    init() { load() }

    // MARK: - Public API

    func recordSession(durationSeconds: TimeInterval) {
        guard durationSeconds > 0 else { return }
        let minutes = durationSeconds / 60
        let day = Calendar.current.startOfDay(for: Date())
        if let idx = entries.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            entries[idx].minutes += minutes
            entries[idx].sessionCount += 1
        } else {
            entries.append(DailyUsage(date: day, minutes: minutes, sessionCount: 1))
        }
        save()
    }

    func reset() {
        entries = []
        save()
    }

    // MARK: - Aggregates

    var todayMinutes: Double { minutes(daysAgo: 0) }
    var yesterdayMinutes: Double { minutes(daysAgo: 1) }

    var todayCost: Double { todayMinutes * Self.pricePerMinute }
    var yesterdayCost: Double { yesterdayMinutes * Self.pricePerMinute }

    var totalMinutes: Double { entries.reduce(0) { $0 + $1.minutes } }
    var totalCost: Double { totalMinutes * Self.pricePerMinute }

    /// Daily minutes for the last 7 days, oldest first, with zero-fill.
    var last7Days: [DailyUsage] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset -> DailyUsage in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            if let entry = entries.first(where: { cal.isDate($0.date, inSameDayAs: day) }) {
                return entry
            }
            return DailyUsage(date: day, minutes: 0, sessionCount: 0)
        }
    }

    private func minutes(daysAgo: Int) -> Double {
        let cal = Calendar.current
        guard let target = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date())) else {
            return 0
        }
        return entries.first(where: { cal.isDate($0.date, inSameDayAs: target) })?.minutes ?? 0
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([DailyUsage].self, from: data) {
            entries = loaded.sorted { $0.date < $1.date }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}

struct DailyUsage: Codable, Identifiable, Hashable, Sendable {
    var id: Date { date }
    var date: Date
    var minutes: Double
    var sessionCount: Int
}
