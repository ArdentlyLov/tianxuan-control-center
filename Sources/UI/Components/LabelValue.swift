// LabelValue.swift

import SwiftUI
import AppKit
import Combine

struct LabelValue: View {
    let label: String
    let value: String
    var mono = true
    var color: Color = Palette.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 11.5).monospaced() : .system(size: 11.5))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

