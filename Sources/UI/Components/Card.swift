import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    var accent: Color? = nil
    var glow: Bool = false
    var radius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.panelTop)
                    .shadow(color: Color.black.opacity(glow ? 0.04 : 0.025), radius: 10, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(accent?.opacity(0.28) ?? Palette.cardStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    var color: Color = Palette.accent
    var code: String? = nil
    var command: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing).font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
        }
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 5)
    }
}
