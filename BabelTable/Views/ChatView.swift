import SwiftUI
import UIKit

/// Side-by-side chat layout: phone lays flat between two people, both reading
/// the same screen. Each utterance becomes a card with the source on top and
/// the translation below.
struct ChatView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// Only auto-scroll on new content while the user is already at the
    /// bottom — yanking the view away mid-read is worse than not following.
    @State private var isNearBottom = true

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
                        EmptyConversationCard(
                            title: placeholderTitle,
                            message: placeholderDescription,
                            systemImage: coordinator.status == .running ? "waveform" : "bubble.left.and.bubble.right",
                            tint: BabelTheme.primary
                        )
                        .padding(.top, 24)
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
                .padding(.horizontal, BabelTheme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 68)
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 80
            } action: { _, nearBottom in
                isNearBottom = nearBottom
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
            .overlay(alignment: .bottomTrailing) {
                if !isNearBottom && (coordinator.openTurn != nil || !coordinator.chatTurns.isEmpty) {
                    Button {
                        scrollToLatest(proxy)
                    } label: {
                        Label("Latest", systemImage: "arrow.down")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(BabelTheme.primary)
                    .padding(16)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isNearBottom)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard isNearBottom else { return }
        scrollToLatest(proxy)
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if coordinator.openTurn != nil {
                proxy.scrollTo("open", anchor: .bottom)
            } else if let last = coordinator.chatTurns.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
        isNearBottom = true
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(sourceTag)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(turn.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                if isLive {
                    Label("Live", systemImage: "waveform")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BabelTheme.live)
                        .symbolEffect(.pulse, options: .repeating)
                }
            }

            Text(turn.sourceText.isEmpty ? "…" : turn.sourceText)
                .font(.body)
                .foregroundStyle(.primary)

            if !turn.bestTranslation.isEmpty || isLive {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(translationTag)
                        .font(.caption.weight(.semibold))
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
                    .font(.body.weight(.medium))
                    .foregroundStyle(turn.bestTranslation.isEmpty ? .secondary : .primary)
                    .animation(.easeInOut(duration: 0.2), value: turn.bestTranslation)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(accent.opacity(0.09), in: .rect(cornerRadius: BabelTheme.radius, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .clipShape(.rect(cornerRadii: .init(topLeading: BabelTheme.radius, bottomLeading: BabelTheme.radius)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: BabelTheme.radius, style: .continuous)
                .stroke(accent.opacity(0.12), lineWidth: 1)
        }
        .contextMenu { copyMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
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
        alignsRight ? BabelTheme.local : BabelTheme.remote
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

    private var accessibilityDescription: String {
        var parts = ["\(sourceTag), \(turn.sourceText.isEmpty ? "Listening" : turn.sourceText)"]
        if !turn.bestTranslation.isEmpty {
            parts.append("\(translationTag), \(turn.bestTranslation)")
        }
        if isLive { parts.append("Live") }
        if turn.isRefined { parts.append("Refined translation") }
        return parts.joined(separator: ". ")
    }
}
