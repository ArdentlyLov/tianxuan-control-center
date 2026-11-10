// Sliders.swift

import SwiftUI
import AppKit
import Combine

// MARK: - 自绘滑杆

struct LevelSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...16
    var step: Double = 1
    var tint: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 9
            let usable = max(geo.size.width - inset * 2, 1)
            let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let knobX = inset + usable * CGFloat(min(max(frac, 0), 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.trackFill)
                    .frame(height: 5)

                Capsule()
                    .fill(tint)
                    .frame(width: max(knobX - inset + 1, 1), height: 5)
                    .offset(x: inset)

                Circle()
                    .fill(Palette.panelTop)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(tint, lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
                    .offset(x: knobX - 7)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let p = min(max(g.location.x - inset, 0), usable)
                    let raw = range.lowerBound + Double(p / usable) * (range.upperBound - range.lowerBound)
                    let snapped = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
                    if snapped != value { value = snapped }
                }
            )
        }
        .frame(height: 22)
    }
}

// MARK: - 电量条

struct BatteryBar: View {
    let percent: Int

    private var color: Color {
        if percent > 60 { return Palette.ok }
        if percent > 20 { return Palette.warn }
        return Palette.bad
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.trackFill)
                Capsule()
                    .fill(color)
                    .frame(width: max(geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100, 4))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - 自绘分段控件

struct SegmentedButtons<Value: Hashable>: View {
    let items: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    selection = items[i].1
                } label: {
                    Text(items[i].0)
                        .font(.system(size: 11, weight: selection == items[i].1 ? .medium : .regular))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selection == items[i].1
                                      ? AnyShapeStyle(Palette.panelTop)
                                      : AnyShapeStyle(Color.clear))
                        )
                        .foregroundStyle(selection == items[i].1 ? Palette.accent : Palette.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.faintFill))
    }
}

