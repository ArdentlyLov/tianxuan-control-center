import SwiftUI

/// 从提供的 SVG 中提取几何徽记，按原始比例居中绘制。
struct TianxuanGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let polygons: [[CGPoint]] = [
            [CGPoint(x: 78, y: 57), CGPoint(x: 78, y: 179), CGPoint(x: 142, y: 216), CGPoint(x: 142, y: 94)],
            [CGPoint(x: 158, y: 103), CGPoint(x: 158, y: 263), CGPoint(x: 221, y: 299), CGPoint(x: 221, y: 139)],
            [CGPoint(x: 382, y: 57), CGPoint(x: 319, y: 93), CGPoint(x: 319, y: 147), CGPoint(x: 382, y: 111)],
            [CGPoint(x: 382, y: 125), CGPoint(x: 319, y: 162), CGPoint(x: 319, y: 216), CGPoint(x: 382, y: 180)],
            [CGPoint(x: 302, y: 103), CGPoint(x: 239, y: 139), CGPoint(x: 239, y: 299), CGPoint(x: 302, y: 263)]
        ]
        let scale = min(rect.width / 304, rect.height / 242)
        let origin = CGPoint(x: rect.minX + (rect.width - 304 * scale) / 2,
                             y: rect.minY + (rect.height - 242 * scale) / 2)
        var path = Path()
        for polygon in polygons {
            for (index, point) in polygon.enumerated() {
                let fitted = CGPoint(x: origin.x + (point.x - 78) * scale,
                                     y: origin.y + (point.y - 57) * scale)
                if index == 0 { path.move(to: fitted) } else { path.addLine(to: fitted) }
            }
            path.closeSubpath()
        }
        return path
    }
}

struct TianxuanEmblem: View {
    var height: CGFloat = 32
    var opacity: Double = 1
    var body: some View {
        TianxuanGlyph().fill(Palette.accent)
            .frame(width: height * 304 / 242, height: height)
            .opacity(opacity)
            .accessibilityLabel("天选徽记")
    }
}
