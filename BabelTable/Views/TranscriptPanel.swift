import SwiftUI

struct TranscriptPanel: View {
    let title: String
    let languageCode: String
    let text: String
    let accent: Color
    let isRunning: Bool
    var isActiveSpeaker: Bool = false

    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// Only auto-scroll on new content while the user is already at the
    /// bottom — yanking the view away mid-read is worse than not following.
    @State private var isNearBottom = true

    private var isRegular: Bool { hSizeClass == .regular }

    /// Larger transcript body text on iPad / regular size class so two people
    /// reading from across a table can actually see it.
    private var transcriptFont: Font {
        isRegular ? .system(size: 28, weight: .regular) : .title3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LanguagePill(languageCode: languageCode, title: title, tint: accent)
                Spacer()
                if isActiveSpeaker {
                    StatusPill(title: "Speaking", systemImage: "waveform", tint: accent, isAnimated: true)
                } else if isRunning {
                    Text("Listening")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if text.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: isRunning ? "waveform" : "text.bubble")
                                    .font(.title2)
                                    .foregroundStyle(accent.opacity(0.7))
                                    .accessibilityHidden(true)
                                Text(placeholder)
                                    .font(transcriptFont)
                                Text(isRunning ? "Translation appears here as soon as the other person speaks." : "The translated conversation will stay readable on this side of the table.")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.secondary)
                        } else {
                            Text(text)
                            .font(transcriptFont)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("transcript")
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 80
                } action: { _, nearBottom in
                    isNearBottom = nearBottom
                }
                .onChange(of: text) { _, _ in
                    guard isNearBottom else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("transcript", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(accent.opacity(isActiveSpeaker ? 0.11 : 0.05), in: .rect(cornerRadius: BabelTheme.radius))
        .overlay {
            RoundedRectangle(cornerRadius: BabelTheme.radius)
                .stroke(accent.opacity(isActiveSpeaker ? 0.35 : 0.10), lineWidth: isActiveSpeaker ? 1.5 : 1)
        }
        .animation(.easeInOut(duration: 0.2), value: isActiveSpeaker)
    }

    private var placeholder: String {
        isRunning ? "Listening…" : "Tap Start to begin translating."
    }

}
