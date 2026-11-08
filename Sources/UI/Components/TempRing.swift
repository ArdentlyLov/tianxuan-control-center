// TempRing.swift

import SwiftUI
import AppKit
import Combine

// MARK: - 温度环（霓虹仪表）

struct TempRing: View {
    let value: Double?
    var size: CGFloat = 132
    var lineWidth: CGFloat = 9

    private var fraction: Double {
        guard let v = value else { return 0 }
        return min(max((v - 30) / 70, 0.02), 1.0)
    }

    // 用 Canvas 分段描边代替 AngularGradient：
    // 锥形渐变会被 CoreGraphics 逐像素软件光栅化（rgba64_shade_conic_RGB），
    // 一圈 280×280 的环单次重绘就要几十毫秒；分段实色描边几乎零成本。
    var body: some View {
        Canvas { ctx, canvasSize in
            drawBase(ctx, canvasSize)
            drawTicks(ctx, canvasSize)
            drawProgress(ctx, canvasSize)
            drawLabels(ctx, canvasSize)
        }
        .frame(width: size, height: size)
    }

    private func geometry(_ canvasSize: CGSize) -> (center: CGPoint, radius: CGFloat) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let radius = min(canvasSize.width, canvasSize.height) / 2 - lineWidth / 2 - 6
        return (center, radius)
    }

    private func drawBase(_ ctx: GraphicsContext, _ canvasSize: CGSize) {
        let (center, radius) = geometry(canvasSize)
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.stroke(Path(ellipseIn: rect), with: .color(Palette.ringBase), lineWidth: lineWidth)
    }

    private func drawTicks(_ ctx: GraphicsContext, _ canvasSize: CGSize) {
        let (center, radius) = geometry(canvasSize)
        var ticks = Path()
        for i in 0..<24 {
            let angle: Double = Double(i) / 24 * 2 * Double.pi - Double.pi / 2
            let length: CGFloat = i % 6 == 0 ? 6 : 3.5
            let outer: CGFloat = radius - lineWidth / 2 - 4
            let inner: CGFloat = outer - length
            ticks.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * outer,
                                   y: center.y + CGFloat(sin(angle)) * outer))
            ticks.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * inner,
                                      y: center.y + CGFloat(sin(angle)) * inner))
        }
        ctx.stroke(ticks, with: .color(Palette.ringTick), lineWidth: 1)
    }

    private func drawProgress(_ ctx: GraphicsContext, _ canvasSize: CGSize) {
        let (center, radius) = geometry(canvasSize)
        let total = fraction
        guard total > 0.005 else { return }
        let segments = 72
        for i in 0..<segments {
            let t0 = Double(i) / Double(segments)
            if t0 >= total { break }
            let t1 = min(Double(i + 1) / Double(segments), total)
            let startAngle = Angle.radians(t0 * 2 * Double.pi - Double.pi / 2)
            let endAngle = Angle.radians(t1 * 2 * Double.pi - Double.pi / 2 + 0.02)
            var arc = Path()
            arc.addArc(center: center, radius: radius,
                       startAngle: startAngle, endAngle: endAngle, clockwise: false)
            let style = StrokeStyle(lineWidth: lineWidth,
                                    lineCap: t1 >= total ? CGLineCap.round : CGLineCap.butt)
            ctx.stroke(arc, with: .color(TempRing.color(at: t0)), style: style)
        }
    }

    private func drawLabels(_ ctx: GraphicsContext, _ canvasSize: CGSize) {
        let (center, radius) = geometry(canvasSize)
        let numberSize = canvasSize.width * 0.30
        let number = Text(value.map { String(format: "%.0f", $0) } ?? "—")
            .font(.system(size: numberSize, weight: .bold).monospacedDigit())
            .foregroundColor(Palette.text)
        ctx.draw(number, at: CGPoint(x: center.x, y: center.y - 2), anchor: .center)

        let unit = Text("°C")
            .font(.system(size: canvasSize.width * 0.10, weight: .medium))
            .foregroundColor(Palette.textTertiary)
        ctx.draw(unit, at: CGPoint(x: center.x, y: center.y + radius * 0.42), anchor: .center)
    }

    /// 冷→热四段插值（原来是 AngularGradient 的色标）
    static func color(at t: Double) -> Color {
        let stops: [(Double, Double, Double, Double)] = [
            (0.00, 0x26, 0xB8, 0xAB),
            (0.55, 0x00, 0x8C, 0x80),
            (0.78, 0xEF, 0xA0, 0x35),
            (1.00, 0xD6, 0x4E, 0x5B)
        ]
        let x: Double = min(max(t, 0), 1)
        for i in 0..<(stops.count - 1) {
            let p0 = stops[i].0
            let p1 = stops[i + 1].0
            if x <= p1 {
                let k: Double = (x - p0) / (p1 - p0)
                let r: Double = (stops[i].1 + (stops[i + 1].1 - stops[i].1) * k) / 255
                let g: Double = (stops[i].2 + (stops[i + 1].2 - stops[i].2) * k) / 255
                let b: Double = (stops[i].3 + (stops[i + 1].3 - stops[i].3) * k) / 255
                return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
            }
        }
        return Palette.bad
    }
}

