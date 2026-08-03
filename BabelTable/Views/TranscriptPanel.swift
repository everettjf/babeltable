import SwiftUI

struct TranscriptPanel: View {
    let title: String
    let languageCode: String
    let text: String
    let accent: Color
    let isRunning: Bool

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isRegular: Bool { hSizeClass == .regular }

    /// Larger transcript body text on iPad / regular size class so two people
    /// reading from across a table can actually see it.
    private var transcriptFont: Font {
        isRegular ? .system(size: 28, weight: .regular) : .title3
    }

    private var titleFont: Font {
        isRegular ? .title3.weight(.semibold) : .headline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(accent)
                Spacer()
                if isRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.15), in: .capsule)
                    .foregroundStyle(accent)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(text.isEmpty ? placeholder : text)
                            .font(transcriptFont)
                            .foregroundStyle(text.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("transcript")
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .onChange(of: text) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("transcript", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(accent.opacity(0.04))
    }

    private var placeholder: String {
        isRunning ? "Listening…" : "Tap Start to begin translating."
    }

    /// Flag for the panel's language; falls back to the uppercased code.
    private var badge: String {
        SupportedLanguages.resolve(languageCode)?.flag ?? languageCode.uppercased()
    }
}
