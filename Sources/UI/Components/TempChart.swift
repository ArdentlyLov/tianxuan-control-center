// TempChart.swift

import SwiftUI
import AppKit
import Combine

// MARK: - 温度图（带纵轴）

struct TempChart: View {
    let values: [Double]
    var color: Color = Palette.accent2
    var lower: Double = 35
    var upper: Double = 100
    var height: CGFloat = 132

    private var labels: [String] {
        (0...3).map { i in
            let v = upper - (upper - lower) * Double(i) / 3.0
            return String(format: "%.0f°", v)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i])
                        .font(.system(size: 8.5).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                    if i < labels.count - 1 { Spacer(minLength: 0) }
                }
            }
            .frame(width: 26, height: height)

            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { i in
                        if i > 0 { Rectangle().fill(Palette.hairline).frame(height: 1) }
                        if i < 3 { Spacer(minLength: 0) }
                    }
                }
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        if i > 0 { Rectangle().fill(Palette.subtle).frame(width: 1) }
                        if i < 6 { Spacer(minLength: 0) }
                    }
                }
                Sparkline(values: values, color: color, lowerBound: lower, upperBound: upper)
            }
            .frame(height: height)
        }
    }
}

