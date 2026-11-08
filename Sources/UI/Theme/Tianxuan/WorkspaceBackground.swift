import SwiftUI
struct TianxuanScrollEdgeOff: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.scrollEdgeEffectHidden(true, for: .all) }
        else { content }
    }
}
struct WorkspaceBackground: View {
    var body: some View {
        Palette.bg.overlay(alignment: .topTrailing) {
            TianxuanGlyph().fill(Palette.accent.opacity(0.025))
                .frame(width: 390, height: 390).rotationEffect(.degrees(-12))
                .offset(x: 90, y: -100)
        }.allowsHitTesting(false)
    }
}
