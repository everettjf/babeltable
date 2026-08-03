import SwiftUI

struct SessionDetailView: View {
    let session: ChatSession

    var body: some View {
        List {
            Section {
                LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                if let ended = session.endedAt {
                    LabeledContent("Ended", value: ended.formatted(date: .abbreviated, time: .standard))
                }
                LabeledContent("Duration", value: session.durationDescription)
                LabeledContent("Languages", value: "\(SupportedLanguages.label(forCode: session.primaryLanguageCode)) ⇄ \(SupportedLanguages.label(forCode: session.secondaryLanguageCode))")
            } header: {
                Text("Session")
            }

            if let chatTurns = session.chatTurns, !chatTurns.isEmpty {
                Section {
                    ForEach(chatTurns) { turn in
                        chatTurnRow(turn)
                    }
                } header: {
                    Text("Conversation")
                }
            }

            Section {
                if session.primaryLines.isEmpty {
                    Text("No transcript")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.primaryLines) { line in
                        transcriptRow(line)
                    }
                }
            } header: {
                Text(SupportedLanguages.byCode(session.primaryLanguageCode)?.nativeName
                     ?? session.primaryLanguageCode)
            }

            Section {
                if session.secondaryLines.isEmpty {
                    Text("No transcript")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.secondaryLines) { line in
                        transcriptRow(line)
                    }
                }
            } header: {
                Text(SupportedLanguages.byCode(session.secondaryLanguageCode)?.nativeName
                     ?? session.secondaryLanguageCode)
            }
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: shareFileURL(),
                    subject: Text(session.displayTitle),
                    preview: SharePreview(
                        session.displayTitle,
                        icon: Image(systemName: "doc.text")
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Share

    /// Writes the conversation as a UTF-8 .txt file in the temp directory and
    /// returns its URL for the share sheet. Recomputed on each body eval; the
    /// system periodically cleans the temp dir so this is safe.
    private func shareFileURL() -> URL {
        let content = buildTranscriptText()
        let stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyy-MM-dd-HHmm"
        let stamp = stampFormatter.string(from: session.startedAt)
        let filename = "BabelTable-\(stamp).txt"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func buildTranscriptText() -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .short

        let timeFmt = DateFormatter()
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .medium

        let primaryName = SupportedLanguages.byCode(session.primaryLanguageCode)?.nativeName
            ?? session.primaryLanguageCode
        let secondaryName = SupportedLanguages.byCode(session.secondaryLanguageCode)?.nativeName
            ?? session.secondaryLanguageCode

        var lines: [String] = []
        lines.append("BabelTable Conversation")
        lines.append("")
        lines.append("Started:   \(dateFmt.string(from: session.startedAt))")
        if let ended = session.endedAt {
            lines.append("Ended:     \(dateFmt.string(from: ended))")
        }
        lines.append("Duration:  \(session.durationDescription)")
        lines.append("Languages: \(primaryName) ⇄ \(secondaryName)")
        lines.append("")
        lines.append("──────────────────────────────")
        lines.append("")

        if let turns = session.chatTurns, !turns.isEmpty {
            for turn in turns {
                let srcLang = languageDisplay(turn.sourceLanguageCode)
                lines.append("[\(timeFmt.string(from: turn.startedAt))] \(srcLang)")
                lines.append(turn.sourceText)
                if !turn.bestTranslation.isEmpty {
                    let dstLang = languageDisplay(turn.translatedLanguageCode)
                    lines.append("→ \(dstLang)")
                    lines.append(turn.bestTranslation)
                }
                lines.append("")
            }
        } else {
            // Older sessions without chatTurns: fall back to per-panel lines.
            if !session.primaryLines.isEmpty {
                lines.append("[\(primaryName)]")
                for line in session.primaryLines {
                    lines.append("[\(timeFmt.string(from: line.timestamp))] \(line.text)")
                }
                lines.append("")
            }
            if !session.secondaryLines.isEmpty {
                lines.append("[\(secondaryName)]")
                for line in session.secondaryLines {
                    lines.append("[\(timeFmt.string(from: line.timestamp))] \(line.text)")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func languageDisplay(_ code: String) -> String {
        guard !code.isEmpty, code != "auto" else { return "?" }
        let normalized = String(code.split(separator: "-").first ?? Substring(code))
        return SupportedLanguages.byCode(normalized)?.nativeName
            ?? SupportedLanguages.byCode(code)?.nativeName
            ?? code.uppercased()
    }

    @ViewBuilder
    private func chatTurnRow(_ turn: ChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(SupportedLanguages.label(forCode: turn.sourceLanguageCode))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15), in: .capsule)
                    .foregroundStyle(.blue)
                Text(turn.startedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if turn.isRefined {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(turn.sourceText)
                .font(.body)
            if !turn.bestTranslation.isEmpty {
                Text("→ \(turn.bestTranslation)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func transcriptRow(_ line: TranscriptLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.text)
                .font(.body)
            Text(line.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
