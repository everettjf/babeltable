import SwiftUI

enum BabelTheme {
    static let primary = Color.indigo
    static let primarySoft = Color.indigo.opacity(0.12)
    static let local = Color.teal
    static let remote = Color.indigo
    static let live = Color.red
    static let warning = Color.orange

    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedBackground = Color(uiColor: .systemBackground)

    static let smallRadius: CGFloat = 12
    static let radius: CGFloat = 18
    static let largeRadius: CGFloat = 24
    static let pagePadding: CGFloat = 16
}

struct BabelCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                tint?.opacity(0.07) ?? BabelTheme.cardBackground,
                in: .rect(cornerRadius: BabelTheme.radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BabelTheme.radius, style: .continuous)
                    .stroke(tint?.opacity(0.18) ?? Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

extension View {
    func babelCard(padding: CGFloat = 16, tint: Color? = nil) -> some View {
        modifier(BabelCardModifier(padding: padding, tint: tint))
    }
}

struct LanguagePill: View {
    let languageCode: String
    let title: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
                .lineLimit(1)
        } icon: {
            Text(SupportedLanguages.resolve(languageCode)?.flag ?? "•")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isAnimated = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: .capsule)
            .symbolEffect(.pulse, options: .repeating, isActive: isAnimated)
            .accessibilityElement(children: .combine)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyConversationCard: View {
    let title: String
    let message: String
    let systemImage: String
    var tint: Color = BabelTheme.primary

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .babelCard(padding: 20, tint: tint)
    }
}
