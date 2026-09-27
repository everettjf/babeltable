import SwiftUI
import Translation

struct OfflineModelsView: View {
    let pair: SessionLanguagePair
    @State private var checkVersion = 0
    @State private var modelStatus: OfflineModels.Status?
    @State private var preparing = false
    @State private var message: String?
    @State private var forward: TranslationSession.Configuration?
    @State private var reverse: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Offline language models", systemImage: "arrow.down.circle")
                .font(.headline)
            Text("Download models once while connected. Speech and translations then stay on this device, including in airplane mode.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("\(SupportedLanguages.name(forCode: pair.primary)) ↔ \(SupportedLanguages.name(forCode: pair.secondary))")
            if preparing { ProgressView("Preparing language models…") }
            else {
                switch modelStatus {
                case .ready: Label("Ready for offline use", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .unsupported: Text("This device or language pair is not supported. Choose different languages.").foregroundStyle(.secondary)
                case .unavailable:
                    Text("Local language services are temporarily unavailable.").foregroundStyle(.secondary)
                    Button("Check again") { modelStatus = nil; checkVersion += 1 }
                case .needsDownload:
                    Button("Download language models") { prepare() }.buttonStyle(.borderedProminent)
                case nil: ProgressView("Checking models…")
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: checkVersion) { modelStatus = await OfflineModels.status(for: pair) }
        .translationTask(forward) { session in
            do {
                try await OfflineModels.prepareSpeech(for: pair)
                try await session.prepareTranslation()
                try Task.checkCancellation()
                reverse = .init(source: .init(identifier: pair.secondary), target: .init(identifier: pair.primary), preferredStrategy: .lowLatency)
            } catch { preparationFailed() }
        }
        .translationTask(reverse) { session in
            do {
                try await session.prepareTranslation()
                try Task.checkCancellation()
                modelStatus = await OfflineModels.status(for: pair)
                preparing = false
                if modelStatus != .ready { message = "Models are not ready yet. Check available storage and try again." }
            } catch { preparationFailed() }
        }
    }

    private func prepare() {
        preparing = true; message = nil
        if forward != nil { forward?.invalidate() }
        else { forward = .init(source: .init(identifier: pair.primary), target: .init(identifier: pair.secondary), preferredStrategy: .lowLatency) }
        reverse = nil
    }
    private func preparationFailed() {
        preparing = false
        message = "Model preparation did not finish. Connect to the internet, check available storage, and retry."
    }
}
