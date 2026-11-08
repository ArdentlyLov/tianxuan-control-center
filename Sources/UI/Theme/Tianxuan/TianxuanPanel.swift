import SwiftUI

struct PanelShape: Shape {
    var radius: CGFloat = 22
    /// 0 = 普通圆角矩形；>0 = 切角尺寸
    var cut: CGFloat = 0
    /// 描边时向内收的量（InsettableShape 用）
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = insetAmount == 0 ? rect
            : rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard cut > 0 else {
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }
        let big = min(cut, min(rect.width, rect.height) / 2.5)
        let small = big * 0.44
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + big, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - small, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + small))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - big))
        p.addLine(to: CGPoint(x: rect.maxX - big, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + small, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - small))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + big))
        p.closeSubpath()
        return p
    }
}

extension PanelShape: InsettableShape {
    func inset(by amount: CGFloat) -> PanelShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// 只画两处大斜边（左上、右下），用来强调机甲切角
struct PanelAccents: Shape {
    var cut: CGFloat = 13

    func path(in rect: CGRect) -> Path {
        let big = min(cut, min(rect.width, rect.height) / 2.5)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + big, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + big))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - big))
        p.addLine(to: CGPoint(x: rect.maxX - big, y: rect.maxY))
        return p
    }
}

/// 标题里的虚线横规：撑满剩余宽度，像工程图的分栏线
struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// 像读一份 天选 的运行时配置，而不是看一个仪表盘。
struct CodeRow: View {
    let key: String
    let value: String
    var size: CGFloat = 10
    var valueColor: Color = Palette.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key)
                .font(.system(size: size - 0.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.accent.opacity(0.78))
                .lineLimit(1)
            Text(value)
                .font(.system(size: size, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

