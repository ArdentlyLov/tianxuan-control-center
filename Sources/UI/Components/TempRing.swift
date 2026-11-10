import SwiftUI

/// 单色温度环。Canvas 避免逐段视图和渐变带来的重绘开销。
struct TempRing: View {
    let value: Double?
    var size: CGFloat = 132
    var lineWidth: CGFloat = 7

    private var fraction: Double {
        guard let value else { return 0 }
        return min(max((value - 30) / 70, 0.02), 1)
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 - lineWidth / 2 - 3
            let rect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(Palette.ringBase), lineWidth: lineWidth)
            if fraction > 0 {
                var arc = Path()
                arc.addArc(center: center, radius: radius,
                           startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + fraction * 360), clockwise: false)
                ctx.stroke(arc, with: .color(Palette.forTemp(value)),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            let number = Text(value.map { String(format: "%.0f", $0) } ?? "—")
                .font(.system(size: canvasSize.width * 0.31, weight: .semibold).monospacedDigit())
                .foregroundColor(Palette.text)
            ctx.draw(number, at: CGPoint(x: center.x, y: center.y - 5))
            let unit = Text("°C")
                .font(.system(size: canvasSize.width * 0.11, weight: .medium))
                .foregroundColor(Palette.textSecondary)
            ctx.draw(unit, at: CGPoint(x: center.x, y: center.y + radius * 0.43))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("温度")
        .accessibilityValue(value.map { String(format: "%.0f °C", $0) } ?? "无数据")
    }
}
