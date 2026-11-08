import SwiftUI

/// 原创天选风格机甲徽记，与应用图标共用同一轮廓。
struct TianxuanGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (0.07,0.19),(0.40,0.19),(0.49,0.30),(0.60,0.19),(0.93,0.19),
            (0.80,0.39),(0.61,0.39),(0.54,0.50),(0.54,0.74),(0.43,0.86),
            (0.43,0.50),(0.36,0.39),(0.20,0.39)
        ]
        var path = Path()
        for (i, p) in points.enumerated() {
            let point = CGPoint(x: rect.minX + p.0 * rect.width, y: rect.minY + p.1 * rect.height)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
struct TianxuanEmblem: View {
    var height: CGFloat = 32
    var opacity: Double = 1
    var body: some View {
        TianxuanGlyph().fill(Palette.accent)
            .frame(width: height, height: height)
            .opacity(opacity)
            .accessibilityLabel("天选徽记")
    }
}
