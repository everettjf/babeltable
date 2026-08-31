import SwiftUI

struct SessionDetailView: View {
    let session: ChatSession

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                summaryCard

                if let turns = session.chatTurns, !turns.isEmpty {
                    SectionHeading(title: "Conversation", subtitle: "\(turns.count) translated turns")
                    ForEach(turns) { turn in
                        ArchivedTurnCard(turn: turn, session: session)
                    }
                } else {
                    legacyTranscript
                }
            }
            .frame(maxWidth: 760)
            .padding(BabelTheme.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .background(BabelTheme.pageBackground)
        .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: transcriptText, subject: Text("BabelTable Conversation")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share conversation as text")
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.startedAt.formatted(date: .complete, time: .omitted))
                        .font(.headline)
                    Text(session.startedAt.formatted(date: .omitted, time: .standard))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(session.durationDescription, systemImage: "clock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BabelTheme.primary)
            }
            HStack(spacing: 7) {
                LanguagePill(languageCode: session.primaryLanguageCode,
                             title: languageName(session.primaryLanguageCode), tint: BabelTheme.local)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                LanguagePill(languageCode: session.secondaryLanguageCode,
                             title: languageName(session.secondaryLanguageCode), tint: BabelTheme.remote)
            }
            Text("Saved privately on this device")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .babelCard(tint: BabelTheme.primary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var legacyTranscript: some View {
        SectionHeading(title: "Transcript", subtitle: "Saved by language in an earlier BabelTable version")
        LegacyTranscriptCard(title: languageName(session.primaryLanguageCode), lines: session.primaryLines, tint: BabelTheme.local)
        LegacyTranscriptCard(title: languageName(session.secondaryLanguageCode), lines: session.secondaryLines, tint: BabelTheme.remote)
    }

    private func languageName(_ code: String) -> String {
        SupportedLanguages.byCode(code)?.nativeName ?? code.uppercased()
    }

    private var transcriptText: String {
        var lines = [
            "BabelTable Conversation",
            "",
            "Started: \(session.startedAt.formatted(date: .abbreviated, time: .standard))",
            "Duration: \(session.durationDescription)",
            "Languages: \(languageName(session.primaryLanguageCode)) ⇄ \(languageName(session.secondaryLanguageCode))",
            ""
        ]
        if let turns = session.chatTurns, !turns.isEmpty {
            for turn in turns {
                lines.append("[\(turn.startedAt.formatted(date: .omitted, time: .standard))] \(languageName(turn.sourceLanguageCode))")
                lines.append(turn.sourceText)
                if !turn.bestTranslation.isEmpty {
                    lines.append("→ \(languageName(turn.translatedLanguageCode)): \(turn.bestTranslation)")
                }
                lines.append("")
            }
        } else {
            for line in (session.primaryLines + session.secondaryLines).sorted(by: { $0.timestamp < $1.timestamp }) {
                lines.append("[\(line.timestamp.formatted(date: .omitted, time: .standard))] \(line.text)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private struct ArchivedTurnCard: View {
    let turn: ChatTurn
    let session: ChatSession

    private var isPrimary: Bool {
        SupportedLanguages.normalize(turn.sourceLanguageCode) == session.primaryLanguageCode
    }

    private var tint: Color { isPrimary ? BabelTheme.local : BabelTheme.remote }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(SupportedLanguages.label(forCode: turn.sourceLanguageCode))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(turn.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Text(turn.sourceText)
                .font(.body)
            if !turn.bestTranslation.isEmpty {
                Divider()
                HStack(spacing: 5) {
                    Text("Translation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if turn.isRefined {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(BabelTheme.primary)
                            .accessibilityLabel("Refined")
                    }
                }
                Text(turn.bestTranslation)
                    .font(.body.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .babelCard(tint: tint)
        .accessibilityElement(children: .combine)
    }
}

private struct LegacyTranscriptCard: View {
    let title: String
    let lines: [TranscriptLine]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)
            if lines.isEmpty {
                Text("No transcript recorded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.text)
                        Text(line.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .babelCard(tint: tint)
    }
}
