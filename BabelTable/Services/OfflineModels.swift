import Foundation
import Speech
import Translation

/// Only explicit model preparation may download assets. Conversation startup never requests downloads.
@MainActor
enum OfflineModels {
    enum Status: Equatable {
        case unsupported, needsDownload, ready
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
        guard let modules = try? await modules(for: pair) else { return .unsupported }
        let availability = LanguageAvailability(preferredStrategy: .lowLatency)
        let forward = await availability.status(from: .init(identifier: pair.primary), to: .init(identifier: pair.secondary))
        let reverse = await availability.status(from: .init(identifier: pair.secondary), to: .init(identifier: pair.primary))
        let speech = await AssetInventory.status(forModules: modules)
        guard forward != .unsupported, reverse != .unsupported, speech != .unsupported else { return .unsupported }
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
