import SwiftUI
import AppKit
import Combine

// MARK: - 概览页：「当前模式」卡（功耗墙模式 + 风扇模式，合成一张）

/// 概览页的一张窄卡：左边显示当前功耗墙档位、右边显示当前风扇档位。
/// 设计为只读状态展示，调节仍去「性能与风扇」页。
struct ModeStatusCard: View {
    @ObservedObject private var power = PowerLimitController.shared
    @ObservedObject private var fan = FanControl.shared
    /// 没有功耗墙接口时显示固件性能模式。
    @ObservedObject private var thermal = ThermalControl.shared

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "当前模式", trailing: "功耗 / 风扇",
                             color: Palette.warn, code: "MISSION", command: "mission --profile")
                HStack(spacing: 0) {
                    modeColumn(power.kextSupported ? "功耗墙" : "性能模式",
                               powerLabel,
                               powerSub,
                               color: power.profile == .quiet ? Palette.teal : Palette.warn)
                        .frame(maxWidth: .infinity)
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: 1, height: 36)
                    modeColumn("风扇", fanLabel, fanSub, color: Palette.teal)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 2)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 108)
        .onAppear {
            power.refreshApplied()
            thermal.refresh()
            fan.refresh()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            thermal.refresh()
            fan.refresh()
        }
    }

    private func modeColumn(_ title: String, _ value: String, _ sub: String,
                            color: Color) -> some View {
        VStack(spacing: 2) {
            if Palette.isTianxuan {
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Palette.accent.opacity(0.8))
            } else {
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textTertiary)
            }
            Text(Palette.isTianxuan ? TianxuanText.code(value) : value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// 当前选中的功耗墙档位名（自定义档未解锁时也不会显示）
    /// 没有 SMU 功耗墙时显示本次连接确认的性能模式。
    private var powerLabel: String {
        if !power.kextSupported {
            return thermal.mode?.title ?? "—"
        }
        return power.profile == .custom && !power.unlocked ? "平衡" : power.profile.label
    }

    private var powerSub: String {
        if !power.kextSupported {
            guard thermal.available else { return Palette.isTianxuan ? "无通道" : "无通道" }
            if ASUSWMIBridge.shared.thermalDevice != nil {
                return thermal.mode == nil
                    ? (Palette.isTianxuan ? "尚未设置" : "尚未设置")
                    : (Palette.isTianxuan ? "固件已接受设置" : "固件已接受设置")
            }
            return Palette.isTianxuan ? "EC 固件回读" : "EC 固件回读"
        }
        if let w = power.appliedWatts {
            return "已限 \(w) W"
        }
        return Palette.isTianxuan ? "未限制" : "未限制"
    }

    private var fanLabel: String {
        guard let name = fan.activePreset else {
            return thermal.available ? "固件自动策略" : "未设置"
        }
        if name == "custom" { return "自定义曲线" }
        return fan.presets?.preset(name)?.label ?? name
    }

    private var fanSub: String {
        if fan.kextBuild?.hasPrefix("VelaAsusWMI") == true {
            return Palette.isTianxuan ? "华硕 WMI 已连接" : "华硕 WMI 已连接"
        }
        let ec = ECFanBridge.shared.isAvailable
        if Palette.isTianxuan {
            return fan.kextLoaded ? "kext 已加载" : (ec ? "EC 直连" : "kext 未加载")
        }
        return fan.kextLoaded ? "kext 已加载" : (ec ? "EC 直连" : "kext 未加载")
    }
}
