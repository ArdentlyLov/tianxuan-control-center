// Controls.swift

import SwiftUI
import AppKit
import Combine

// MARK: - 键盘背光档位

struct LevelDots: View {
    let level: Int
    let maxLevel: Int
    var onSelect: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<maxLevel, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(i < level ? Palette.accent : Palette.trackFill)
                    .frame(height: 10)
                    .onTapGesture { onSelect?(i + 1) }
            }
        }
    }
}

// MARK: - 能力行

struct CapabilityRow: View {
    let cap: Capability

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 状态点用「外圈淡色 + 内圈实心」画柔光，不用 `.shadow`：
            // 每行一个阴影 = 每行一层离屏模糊，滚动 / 重建时都要重算，白白拖慢。
            Circle()
                .fill(Palette.forStatus(cap.status).opacity(0.22))
                .frame(width: 11, height: 11)
                .overlay {
                    Circle()
                        .fill(Palette.forStatus(cap.status))
                        .frame(width: 6, height: 6)
                }
                .padding(.top, 3.5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cap.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Text(cap.status.label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.4)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                                .fill(Palette.forStatus(cap.status).opacity(0.14))
                        )
                        .foregroundStyle(Palette.forStatus(cap.status))
                }
                Text(cap.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(cap.backend)
                    .font(.system(size: 9.5).monospaced())
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 标签

struct Pill: View {
    let text: String
    var color: Color = Palette.accent2

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(color.opacity(0.10))
            )
            .foregroundStyle(color)
    }
}

// MARK: - 按钮

struct GrayButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent
                          ? Palette.buttonAccent.opacity(configuration.isPressed ? 0.85 : 1)
                          : (configuration.isPressed ? Palette.subtle : Palette.panelTop))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Palette.hairline, lineWidth: 1)
            )
            .foregroundStyle(prominent ? Color.white : Palette.text)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }
}
