import SwiftUI
import AppKit
import Combine

// MARK: - 界面：功耗墙卡片（整段放进「性能与风扇」页即可）

struct PowerLimitCard: View {
    @ObservedObject private var controller = PowerLimitController.shared
    @State private var draftCustom: Double = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "功耗墙",
                         trailing: controller.kextSupported
                             ? (controller.backend == .rapl ? "RAPL" : "SMU")
                             : "无此通道",
                         command: "power --limit")

            if !controller.kextSupported {
                // 两条通道都没有时，与其摆一排点了没反应的档位按钮，
                // 不如说清楚缺什么、退路是什么。
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("没有可用的功耗墙通道，无法按瓦数限制")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(ECFanBridge.shared.isAvailable
                             ? "Intel 机型需要 AsusECTool.kext v1.4.0 及以上提供 MSR 通道（RAPL 0x610）；临时可用上方「性能模式」的 EC 三档。"
                             : "需要 SMCAsusFan.kext v20-stapm 及以上（AFsC / AFsw），或 AsusECTool.kext v1.4.0 及以上提供 MSR 通道。")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 11) {
                        profileRow

                        if controller.profile == .custom {
                            customSlider
                        }

                        Text(controller.profile == .custom && !controller.unlocked
                             ? "自定义档默认上锁：在「高级功能」页打开「自定义功耗墙」开关、确认风险后可用"
                             : controller.profile.hint)
                            .font(.system(size: 9.5))
                            .foregroundStyle(controller.profile == .custom && !controller.unlocked
                                             ? Palette.warn
                                             : Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        statusLine

                        actionRow

                        // RAPL 才有「重启后要写回」的问题（SMC 值的持久化由 SilentApply 管）
                        if controller.backend == .rapl {
                            Divider().overlay(Palette.hairline)
                            persistRow
                        }

                        if let m = controller.message {
                            Text(m)
                                .font(.system(size: 10))
                                .foregroundStyle(m.hasPrefix("已") ? Palette.ok : Palette.bad)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(footerText)
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear {
            draftCustom = Double(controller.customWatts)
            controller.refreshApplied()
        }
    }

    // MARK: 子视图

    /// 底部说明随通道变化：SMC 那条「只降不升 + powlimit.sh」的说法对 RAPL 不成立
    private var footerText: String {
        switch controller.backend {
        case .smc:
            return "只降不升，上限 \(PowerLimitSpec.maxW)W。重启或睡眠唤醒后会回到默认，想一直保持请在终端执行：sudo powlimit.sh install"
        case .rapl:
            return "范围 \(PowerLimitSpec.minW)–\(PowerLimitSpec.maxW)W，PL1 与 PL2 一起压（只压 PL1 的话爆发期仍会冲到 PL2）。写的是 CPU 寄存器，立即生效；重启后固件会重新编程回标称值 —— 想一直保持就打开上面的「登录时自动保持」。「恢复默认」会写回本程序首次读到的原值。"
        case .none:
            return ""
        }
    }

    private var profileRow: some View {
        HStack(spacing: 7) {
            ForEach(PowerProfile.allCases) { p in
                Button {
                    controller.select(p)
                } label: {
                    VStack(spacing: 2) {
                        Text(p.label)
                            .font(.system(size: 10.5, weight: .medium))
                        if p == .custom && !controller.unlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8.5))
                                .frame(height: 11)
                                .opacity(0.8)
                        } else if let w = p.watts {
                            Text("\(w)W")
                                .font(.system(size: 9, design: .monospaced))
                                .opacity(0.75)
                        } else {
                            Text("\(controller.customWatts)W")
                                .font(.system(size: 9, design: .monospaced))
                                .opacity(0.75)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(controller.profile == p
                                  ? Palette.accent.opacity(0.18)
                                  : Palette.panelTop.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(controller.profile == p
                                    ? Palette.accent.opacity(0.42)
                                    : Palette.cardStroke, lineWidth: 0.8)
                    )
                    .foregroundStyle(controller.profile == p ? Palette.accent : Palette.textSecondary)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("自定义功耗")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("\(Int(draftCustom)) W")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.accent)
            }
            // 显式写 onEditingChanged：Slider 另有 label 参数，用尾随闭包会被解析到 label 上
            Slider(value: $draftCustom,
                   in: Double(PowerLimitSpec.minW)...Double(PowerLimitSpec.maxW),
                   step: 1,
                   onEditingChanged: { editing in
                       if !editing { controller.setCustom(Int(draftCustom)) }
                   })
            .accentColor(Palette.accent)
            HStack {
                Text("\(PowerLimitSpec.minW)W")
                Spacer()
                Text("\(PowerLimitSpec.maxW)W")
            }
            .font(.system(size: 8.5))
            .foregroundStyle(Palette.textTertiary)
        }
        .padding(.vertical, 2)
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(controller.appliedWatts == nil ? Palette.textTertiary : Palette.ok)
                    .frame(width: 5, height: 5)
                Text(controller.appliedWatts.map { "当前：已限 \($0)W" }
                     ?? "当前：默认功耗墙（未限制）")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
            }
            // RAPL 通道能直接读寄存器。这里刻意把「标称」和「实测」分成两行：
            // 175W 是固件写进 0x610 的上限值，跟这台机器真能吃到多少（≈54W）是两回事，
            // 混成一行「硬件回读 PL1 175W」最容易被读成「这机能跑 175W」。
            if let p1 = controller.hardwarePL1 {
                HStack(alignment: .top, spacing: 6) {
                    Text("标称")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 22, alignment: .leading)
                    Text("PL1 \(p1)W · PL2 \(controller.hardwarePL2 ?? p1)W（固件写入的上限值）")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 6) {
                    Text("实测")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 22, alignment: .leading)
                    Text(measuredText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(controller.measuredCeiling == nil
                                         ? Palette.textTertiary : Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 目标高于实测上限 = 这个档位实际达不到，说清楚比让人以为没生效强
                if let ceiling = controller.measuredCeiling,
                   controller.targetWatts > ceiling {
                    Text("目标 \(controller.targetWatts)W 高于实测上限，实际会被压住在 \(ceiling)W 附近")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if controller.lockedByFirmware {
                Text("MSR 0x610 的 lock 位已置位：硬件会忽略写入，需在 BIOS 解锁功耗墙")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var measuredText: String {
        if controller.measuring { return "正在跑满载实测，约 10 秒…" }
        guard let w = controller.measuredCeiling else {
            return "没测过 · 点「测上限」跑一段满载量一次"
        }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        let at = controller.measuredAt.map { "（\(f.string(from: $0))）" } ?? ""
        return "满载约 \(w)W\(at)"
    }

    /// 「登录时自动保持」开关（RAPL 专有：重启后固件会重新编程回标称值）
    private var persistRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("登录时自动保持")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                Text(controller.persistEnabled
                     ? "已装后台项：登录时按当前档位写回 0x610（不需要管理员权限）"
                     : "重启后固件会把它冲回标称值；打开这个才会自动写回")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { controller.persistEnabled },
                set: { controller.setPersist($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Palette.accent)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                controller.apply()
            } label: {
                Group {
                    if controller.applying {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Text("应用 \(controller.targetWatts)W")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 5)
                .background(Capsule().fill(Palette.accent.opacity(0.18)))
                .overlay(Capsule().stroke(Palette.accent.opacity(0.36), lineWidth: 0.8))
                .foregroundStyle(Palette.accent)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(controller.applying || !controller.kextSupported)
            .opacity(controller.kextSupported ? 1 : 0.45)

            Button {
                controller.restore()
            } label: {
                Text("恢复默认")
                    .font(.system(size: 10.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .disabled(controller.applying || !controller.kextSupported)

            if controller.backend == .rapl {
                Button {
                    controller.measureCeiling()
                } label: {
                    Text(controller.measuring ? "实测中…" : "测上限")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.measuring ? Palette.textTertiary : Palette.textSecondary)
                .disabled(controller.measuring || controller.applying)
            }

            Spacer()
        }
    }
}

