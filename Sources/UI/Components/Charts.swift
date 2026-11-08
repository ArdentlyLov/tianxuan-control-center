// Charts.swift

import SwiftUI
import AppKit
import Combine

// MARK: - 折线图（带发光）

/// 曲线背景的坐标系：左侧竖轴 + 底部横轴 + 几条虚线网格。
/// 全部用一条 `Path` 一次描边（不堆 Rectangle / Divider），逐帧几乎零成本。
struct ChartAxes: View {
    /// 水平网格线条数（不含两条轴）
    var rows: Int = 3
    /// 竖向网格线条数
    var columns: Int = 4
    /// 网格是否画出来（只留两条轴时关掉更干净）
    var grid: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                if grid {
                    // 水平虚线：用「距底 1/(n+1)」等分，末条不会贴在轴线上
                    Path { p in
                        for i in 1...max(rows, 1) {
                            let y = h * CGFloat(i) / CGFloat(rows + 1)
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                    }
                    .stroke(Palette.ringTick.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                    // 竖向虚线更淡，避免和曲线抢注意力
                    Path { p in
                        for i in 1...max(columns, 1) {
                            let x = w * CGFloat(i) / CGFloat(columns + 1)
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: h))
                        }
                    }
                    .stroke(Palette.ringTick.opacity(0.22),
                            style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
                }

                // 两条实心轴：左竖轴 + 底横轴（比网格实一档，才有「坐标轴」的感觉）
                Path { p in
                    p.move(to: CGPoint(x: 0.5, y: 0))
                    p.addLine(to: CGPoint(x: 0.5, y: h - 0.5))
                    p.move(to: CGPoint(x: 0, y: h - 0.5))
                    p.addLine(to: CGPoint(x: w, y: h - 0.5))
                }
                .stroke(Palette.ringTick, lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.accent2
    var lowerBound: Double = 30
    var upperBound: Double = 100
    /// false = 只画发光线，不填面积（小卡片用，避免整块色块）
    var filled: Bool = true
    /// 背景坐标轴（左竖轴 + 底横轴 + 虚线网格）
    var axes: Bool = false

    var body: some View {
        GeometryReader { geo in
            let pts = points(size: geo.size)
            ZStack {
                if axes {
                    // 网格密度随可用高度变：小图形少画几根，否则一屏全是虚线
                    ChartAxes(rows: geo.size.height >= 60 ? 3 : 2,
                              columns: geo.size.width >= 280 ? 4 : 3)
                }
                if pts.count > 1 {
                    if filled {
                        area(pts, size: geo.size)
                            .fill(LinearGradient(colors: [color.opacity(0.16), color.opacity(0.0)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                    // 用「宽而淡」的第二条线模拟辉光：
                    // 比 .shadow 便宜得多（阴影每帧都要离屏模糊，是这套界面最大的 GPU 开销）
                    Self.smoothPath(pts, in: geo.size)
                        .stroke(color.opacity(0.20),
                                style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    Self.smoothPath(pts, in: geo.size)
                        .stroke(color,
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                } else {
                    Text("等待采样…")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// 按像素宽度降采样：最多 1 点 / 2px，用峰值池化保留尖峰
    private func points(size: CGSize) -> [CGPoint] {
        guard values.count > 1, size.width > 1, size.height > 1 else { return [] }
        let limit = max(2, Int(size.width / 2))
        let data = Self.downsample(values, to: limit)
        let span = max(upperBound - lowerBound, 1)
        let stepX = size.width / CGFloat(max(data.count - 1, 1))
        return data.enumerated().map { idx, v in
            let clamped = min(max(v, lowerBound), upperBound)
            let y = size.height - CGFloat((clamped - lowerBound) / span) * size.height
            return CGPoint(x: CGFloat(idx) * stepX, y: y)
        }
    }

    static func downsample(_ values: [Double], to limit: Int) -> [Double] {
        guard values.count > limit, limit > 2 else { return values }
        let bucket = Double(values.count) / Double(limit)
        var out: [Double] = []
        out.reserveCapacity(limit)
        for i in 0..<limit {
            let lo = min(values.count - 1, Int(Double(i) * bucket))
            let hi = min(values.count, max(lo + 1, Int(Double(i + 1) * bucket)))
            var peak = values[lo]
            for j in lo..<hi where abs(values[j]) > abs(peak) { peak = values[j] }
            out.append(peak)
        }
        return out
    }

    /// Catmull-Rom → 三次贝塞尔：把折线变成**过所有采样点**的平滑曲线。
    /// 控制点 y 夹在画布内 —— Path 不会被自动裁剪，不夹的话尖峰数据会把曲线甩出边框。
    static func smoothPath(_ pts: [CGPoint], in size: CGSize, tension: CGFloat = 1.0) -> Path {
        var p = Path()
        guard pts.count > 1 else { return p }
        p.move(to: pts[0])
        guard pts.count > 2 else {
            p.addLine(to: pts[1])
            return p
        }
        let k = tension / 6
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            var c1 = CGPoint(x: p1.x + (p2.x - p0.x) * k, y: p1.y + (p2.y - p0.y) * k)
            var c2 = CGPoint(x: p2.x - (p3.x - p1.x) * k, y: p2.y - (p3.y - p1.y) * k)
            c1.y = min(max(c1.y, 0), size.height)
            c2.y = min(max(c2.y, 0), size.height)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }

    /// 面积填充：上沿走同一条平滑曲线，再落到底边闭合
    private func area(_ pts: [CGPoint], size: CGSize) -> Path {
        guard let first = pts.first, let last = pts.last else { return Path() }
        var p = Self.smoothPath(pts, in: size)
        p.addLine(to: CGPoint(x: last.x, y: size.height))
        p.addLine(to: CGPoint(x: first.x, y: size.height))
        p.closeSubpath()
        return p
    }
}

/// 心电监护仪风格的 CPU 频率波形：绿色描边 + 细网格 + 末端扫描光点，
/// 把频率随时间的变化画成类似心电图的滚动轨迹（频率本身不是周期信号，
/// 这里只借用监护仪「绿线 + 网格 + 扫描」的视觉语言）。
struct FreqECG: View {
    let values: [Double]
    var color: Color = Palette.ok
    var lower: Double = 0
    var upper: Double = 5.5
    var height: CGFloat = 60
    /// 背景坐标轴（与 Sparkline 共用同一个 ChartAxes）
    var axes: Bool = false

    var body: some View {
        GeometryReader { geo in
            let pts = Self.points(values: values, size: geo.size, lower: lower, upper: upper)
            ZStack {
                if axes {
                    ChartAxes(rows: geo.size.height >= 60 ? 3 : 2,
                              columns: geo.size.width >= 280 ? 4 : 3)
                }
                if pts.count > 1 {
                    // 宽而淡的辉光（比 .shadow 便宜，避免每帧离屏模糊）
                    Sparkline.smoothPath(pts, in: geo.size)
                        .stroke(color.opacity(0.18),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    Sparkline.smoothPath(pts, in: geo.size)
                        .stroke(color,
                                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    // 末端扫描光点
                    if let last = pts.last {
                        Circle()
                            .fill(color)
                            .frame(width: 4.5, height: 4.5)
                            .position(last)
                            .shadow(color: color, radius: 5)
                    }
                } else {
                    Text("等待采样…")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: height)
    }

    private static func points(values: [Double], size: CGSize, lower: Double, upper: Double) -> [CGPoint] {
        guard values.count > 1, size.width > 1, size.height > 1 else { return [] }
        let limit = max(2, Int(size.width / 2))
        let data = Sparkline.downsample(values, to: limit)
        let span = max(upper - lower, 1)
        let stepX = size.width / CGFloat(max(data.count - 1, 1))
        return data.enumerated().map { idx, v in
            let clamped = min(max(v, lower), upper)
            let y = size.height - CGFloat((clamped - lower) / span) * size.height
            return CGPoint(x: CGFloat(idx) * stepX, y: y)
        }
    }
}

