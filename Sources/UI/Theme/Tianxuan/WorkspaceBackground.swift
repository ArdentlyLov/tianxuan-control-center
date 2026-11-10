import SwiftUI
struct TianxuanScrollEdgeOff: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.scrollEdgeEffectHidden(true, for: .all) }
        else { content }
    }
}
struct WorkspaceBackground: View {
    var body: some View {
        Palette.bg.allowsHitTesting(false)
    }
}
