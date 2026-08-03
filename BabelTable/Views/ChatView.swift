import SwiftUI
import UIKit

/// Side-by-side chat layout: phone lays flat between two people, both reading
/// the same screen. Each utterance becomes a card with the source on top and
/// the translation below.
struct ChatView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// Cap chat column width on iPad / wide layouts so bubbles stay readable
    /// instead of spanning a 1024pt+ screen.
    private var contentMaxWidth: CGFloat {
        hSizeClass == .regular ? 760 : .infinity
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if coordinator.chatTurns.isEmpty && coordinator.openTurn == nil {
                        ContentUnavailableView(
                            placeholderTitle,
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text(placeholderDescription)
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(coordinator.chatTurns) { turn in
                            ChatTurnBubble(
                                turn: turn,
                                primaryLanguageCode: coordinator.primaryLanguageCode,
                                secondaryLanguageCode: coordinator.secondaryLanguageCode
                            )
                            .id(turn.id)
                        }
                        if let drainingTurn = coordinator.drainingTurn {
                            // Input is closed but translation may still be streaming.
                            ChatTurnBubble(
                                turn: drainingTurn,
                                primaryLanguageCode: coordinator.primaryLanguageCode,
                                secondaryLanguageCode: coordinator.secondaryLanguageCode
                            )
                            .id(drainingTurn.id)
                        }
                        if let openTurn = coordinator.openTurn {
                            ChatTurnBubble(
                                turn: openTurn,
                                primaryLanguageCode: coordinator.primaryLanguageCode,
                                secondaryLanguageCode: coordinator.secondaryLanguageCode,
                                isLive: true
                            )
                            .id("open")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: coordinator.chatTurns.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: coordinator.openTurn?.sourceText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: coordinator.openTurn?.translatedText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: coordinator.drainingTurn?.translatedText) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if coordinator.openTurn != nil {
                proxy.scrollTo("open", anchor: .bottom)
            } else if let last = coordinator.chatTurns.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var placeholderTitle: String {
        coordinator.status == .running ? "Listening…" : "Side-by-side chat"
    }

    private var placeholderDescription: String {
        coordinator.status == .running
            ? "Speak in either language and the translation will appear here."
            : "Tap Start to begin. Each utterance shows what was said and its translation."
    }
}

private struct ChatTurnBubble: View {
    @Environment(AppSettings.self) private var settings
    let turn: ChatTurn
    let primaryLanguageCode: String
    let secondaryLanguageCode: String
    var isLive: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if alignsRight { Spacer(minLength: 40) }

            bubbleColumn
                .frame(maxWidth: 560, alignment: alignsRight ? .trailing : .leading)

            if !alignsRight { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubbleColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(sourceTag)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.18), in: .capsule)
                    .foregroundStyle(accent)
                Text(turn.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if isLive {
                    Circle().fill(.red).frame(width: 5, height: 5)
                }
            }

            Text(turn.sourceText.isEmpty ? "…" : turn.sourceText)
                .font(.body)
                .foregroundStyle(.primary)

            if !turn.bestTranslation.isEmpty || isLive {
                Divider().padding(.vertical, 2)
                HStack(spacing: 6) {
                    Text(translationTag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if turn.isRefined {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Refined translation")
                    }
                    Spacer(minLength: 0)
                }
                Text(turn.bestTranslation.isEmpty ? "…" : turn.bestTranslation)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .animation(.easeInOut(duration: 0.2), value: turn.bestTranslation)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accent.opacity(0.10), in: .rect(cornerRadius: 14))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .clipShape(.rect(cornerRadii: .init(topLeading: 14, bottomLeading: 14)))
        }
        .contextMenu { copyMenu }
    }

    @ViewBuilder
    private var copyMenu: some View {
        if !turn.sourceText.isEmpty {
            Button {
                UIPasteboard.general.string = turn.sourceText
            } label: {
                Label("Copy \(sourceCopyLabel)", systemImage: "doc.on.doc")
            }
        }
        if !turn.bestTranslation.isEmpty {
            Button {
                UIPasteboard.general.string = turn.bestTranslation
            } label: {
                Label("Copy \(translatedCopyLabel)", systemImage: "doc.on.doc")
            }
        }
        if !turn.sourceText.isEmpty && !turn.bestTranslation.isEmpty {
            Divider()
            Button {
                UIPasteboard.general.string = "\(turn.sourceText)\n\n\(turn.bestTranslation)"
            } label: {
                Label("Copy both", systemImage: "doc.on.doc.fill")
            }
        }
    }

    private var sourceCopyLabel: String {
        SupportedLanguages.name(forCode: turn.sourceLanguageCode)
    }

    private var translatedCopyLabel: String {
        SupportedLanguages.name(forCode: turn.translatedLanguageCode)
    }

    private var detectedNormalized: String {
        SupportedLanguages.normalize(turn.sourceLanguageCode)
    }

    private var alignsRight: Bool {
        detectedNormalized == primaryLanguageCode
    }

    private var accent: Color {
        alignsRight ? .green : .blue
    }

    /// True when the side reading this bubble is the primary (your) speaker.
    private var isPrimarySide: Bool { alignsRight }

    private var useSpeakerNames: Bool { settings.speakerLabelStyle == .speaker }

    private var sourceTag: String {
        if useSpeakerNames {
            return isPrimarySide ? settings.primarySpeakerName : settings.secondarySpeakerName
        }
        return SupportedLanguages.label(forCode: turn.sourceLanguageCode)
    }

    private var translationTag: String {
        if useSpeakerNames {
            // Translation is for the other person.
            let recipient = isPrimarySide ? settings.secondarySpeakerName : settings.primarySpeakerName
            return "→ \(recipient)"
        }
        guard !turn.translatedLanguageCode.isEmpty else { return "" }
        return "→ \(SupportedLanguages.label(forCode: turn.translatedLanguageCode))"
    }
}
