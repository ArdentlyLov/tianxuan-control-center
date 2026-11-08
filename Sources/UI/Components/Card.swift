import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var accent: Color? = nil
    var glow: Bool = false
    var radius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                PanelShape(radius: radius, cut: 14)
                    .fill(LinearGradient(colors: [Palette.panelTop, Palette.panelBottom],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Color.black.opacity(Palette.isTianxuan ? 0.035 : 0.08), radius: 12, y: 5)
            }
            .overlay {
                PanelShape(radius: radius, cut: 14)
                    .strokeBorder(Palette.cardStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                PanelAccents(cut: 14)
                    .stroke(accent ?? Palette.accent.opacity(glow ? 0.8 : 0.42), lineWidth: 2)
                    .padding(1).allowsHitTesting(false)
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
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 3, height: 13)
            Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
        }
    }
}
