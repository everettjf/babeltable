import Foundation
import Speech
import Translation

/// Only explicit model preparation may download assets. Conversation startup never requests downloads.
@MainActor
enum OfflineModels {
    enum Status: Equatable {
        case unsupported, needsDownload, ready, unavailable
    }

    static func locale(for code: String) async -> Locale? {
        let identifier = code == "zh" ? "zh-CN" : code
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
    }

    static func modules(for pair: SessionLanguagePair) async throws -> [SpeechTranscriber] {
        guard pair.primary != pair.secondary, SpeechTranscriber.isAvailable,
              let primary = await locale(for: pair.primary),
              let secondary = await locale(for: pair.secondary) else { throw OfflineError.unsupported }
        return [primary, secondary].map { SpeechTranscriber(locale: $0, preset: .progressiveTranscription) }
    }

    static func status(for pair: SessionLanguagePair) async -> Status {
        await settledStatus(probe: { await probeStatus(for: pair) })
    }

    /// Apple's availability APIs can return missing/unsupported while their XPC service starts.
    /// Only Ready is accepted immediately. A negative result must remain stable across retries.
    static func settledStatus(
        probe: () async -> Status,
        wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(600)) }
    ) async -> Status {
        var samples: [Status] = []
        for attempt in 0..<3 {
            guard !Task.isCancelled else { return .unavailable }
            let status = await probe()
            if status == .ready { return .ready }
            samples.append(status)
            if attempt < 2 {
                do { try await wait() } catch { return .unavailable }
            }
        }
        guard let first = samples.first, samples.allSatisfy({ $0 == first }) else { return .unavailable }
        return first
    }

    private static func probeStatus(for pair: SessionLanguagePair) async -> Status {
        guard pair.primary != pair.secondary, SpeechTranscriber.isAvailable else { return .unsupported }
        // An empty service catalog is not evidence that the user's language is unsupported.
        guard !(await SpeechTranscriber.supportedLocales).isEmpty else { return .unavailable }
        guard let modules = try? await modules(for: pair) else { return .unsupported }
        let availability = LanguageAvailability(preferredStrategy: .lowLatency)
        let languages = await availability.supportedLanguages
        guard !languages.isEmpty else { return .unavailable }
        let forward = await availability.status(from: .init(identifier: pair.primary), to: .init(identifier: pair.secondary))
        let reverse = await availability.status(from: .init(identifier: pair.secondary), to: .init(identifier: pair.primary))
        let speech = await AssetInventory.status(forModules: modules)
        guard forward != .unsupported, reverse != .unsupported, speech != .unsupported else { return .unsupported }
        if speech == .downloading { return .unavailable }
        return forward == .installed && reverse == .installed && speech == .installed ? .ready : .needsDownload
    }

    static func reserveSpeech(for pair: SessionLanguagePair) async throws {
        let modules = try await modules(for: pair)
        // Reserve only this pair; changing pairs releases reservations, not installed files.
        let wanted = modules.flatMap(\.selectedLocales)
        for old in await AssetInventory.reservedLocales where !wanted.contains(old) {
            await AssetInventory.release(reservedLocale: old)
        }
        for locale in wanted { try await AssetInventory.reserve(locale: locale) }
    }

    static func prepareSpeech(for pair: SessionLanguagePair) async throws {
        try await reserveSpeech(for: pair)
        let modules = try await modules(for: pair)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
    }
}
