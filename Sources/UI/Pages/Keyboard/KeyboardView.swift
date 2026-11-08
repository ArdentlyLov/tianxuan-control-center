// KeyboardView.swift

import SwiftUI
import AppKit
import Combine

// MARK: - 键盘背光

struct KeyboardView: View {
    @EnvironmentObject var store: SensorStore

    private var presets: [(String, Int)] {
        switch store.kbdMaxLevel {
        case 3:  return [("关", 0), ("低", 1), ("中", 2), ("高", 3)]
        case 16: return [("关", 0), ("低", 4), ("中", 8), ("高", 12), ("最大", 16)]
        default: return []
        }
    }

    private var binding: Binding<Double> {
        Binding(
            get: { Double(store.kbdLevel) },
            set: { store.setKeyboardBacklight(Int($0.rounded())) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "键盘背光",
                         trailing: store.kbdMaxLevel > 0
                            ? "\(store.kbdMode.label) · 0–\(store.kbdMaxLevel) 档"
                            : "不可控")

            if store.kbdMaxLevel == 0 {
                unavailableCard
            } else {
                controlCard
            }

            if let err = store.kbdError {
                Card(padding: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.warn)
                        Text(err)
                            .font(.system(size: 11.5))
                            .textSelection(.enabled)
                    }
                }
            }

            channelCard

            AuraPanel()
        }
    }

    // MARK: 正常可调

    private var controlCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.kbdLevel)")
                        .font(.system(size: 46, weight: .semibold).monospacedDigit())
                        .foregroundStyle(store.kbdLevel > 0 ? Palette.accent : Palette.textSecondary)
                    Text("/ \(store.kbdMaxLevel)")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    if store.kbdBusy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("下发中…")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }

                LevelDots(level: store.kbdLevel, maxLevel: store.kbdMaxLevel) {
                    store.setKeyboardBacklight($0)
                }
                .frame(height: 20)

                if store.kbdMaxLevel > 3 {
                    LevelSlider(value: binding, range: 0...Double(store.kbdMaxLevel), step: 1)
                }

                HStack(spacing: 8) {
                    ForEach(presets.indices, id: \.self) { i in
                        Button(presets[i].0) { store.setKeyboardBacklight(presets[i].1) }
                            .buttonStyle(GrayButtonStyle(prominent: store.kbdLevel == presets[i].1))
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: 不可控

    private var unavailableCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: permissionIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(permissionColor)
                    Text(permissionTitle)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(permissionDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    switch store.kbdPermission {
                    case .needsRestart:
                        Button("立即重启") { HIDBacklight.relaunch() }
                            .buttonStyle(GrayButtonStyle(prominent: true))
                        Button("重置授权") {
                            _ = HIDBacklight.resetPermission()
                            _ = HIDBacklight.requestPermission()
                            store.recheckBacklightPermission()
                        }
                        .buttonStyle(GrayButtonStyle())
                        Button("重新检测") { store.recheckBacklightPermission() }
                            .buttonStyle(GrayButtonStyle())

                    case .busy:
                        Button("重新检测") { store.recheckBacklightPermission() }
                            .buttonStyle(GrayButtonStyle(prominent: true))

                    case .denied:
                        Button("打开系统设置") {
                            if let url = HIDBacklight.privacySettingsURL { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(GrayButtonStyle(prominent: true))
                        Button("重置授权并重新申请") {
                            _ = HIDBacklight.resetPermission()
                            _ = HIDBacklight.requestPermission()
                            store.recheckBacklightPermission()
                        }
                        .buttonStyle(GrayButtonStyle())

                    case .notDetermined:
                        Button("申请权限") {
                            _ = HIDBacklight.requestPermission()
                        }
                        .buttonStyle(GrayButtonStyle(prominent: true))
                        Button("打开系统设置") {
                            if let url = HIDBacklight.privacySettingsURL { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(GrayButtonStyle())

                    default:
                        Button("重新检测") { store.recheckBacklightPermission() }
                            .buttonStyle(GrayButtonStyle())
                    }

                    if store.kbdPermission == .needsRestart || store.kbdPermission == .denied
                        || store.kbdPermission == .notDetermined {
                        Button("重新检测") { store.recheckBacklightPermission() }
                            .buttonStyle(GrayButtonStyle())
                    }
                    Spacer()
                }

                Text(permissionHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 权限文案

    private var permissionIcon: String {
        switch store.kbdPermission {
        case .needsRestart: return "arrow.clockwise.circle"
        case .busy: return "exclamationmark.triangle"
        case .denied: return "lock.slash"
        case .notDetermined: return "lock.shield"
        case .noDevice: return "keyboard.slash"
        default: return "keyboard.slash"
        }
    }

    private var permissionColor: Color {
        switch store.kbdPermission {
        case .needsRestart: return Palette.accent2
        case .noDevice: return Palette.textTertiary
        default: return Palette.warn
        }
    }

    private var permissionTitle: String {
        switch store.kbdPermission {
        case .needsRestart: return "已授权，但当前进程还没生效"
        case .busy: return "背光设备被其他进程占用"
        case .denied: return "「输入监控」权限被拒绝"
        case .notDetermined: return "还没有拿到「输入监控」权限"
        case .noDevice: return "没有找到 Aura HID 控制器"
        default: return "这台机器在 macOS 下没有可用的背光通道"
        }
    }

    private var permissionDetail: String {
        switch store.kbdPermission {
        case .busy:
            return "Aura 控制器已经能打开到一半，但被别的进程独占了（kIOReturnExclusiveAccess）。常见原因是还开着一个旧的 天选控制中心 实例，或者别的键盘灯工具在跑。"
        case .needsRestart:
            return "系统设置里已经勾选了本程序，macOS 也确认授权状态是 granted，但这一次进程启动时还没读到这条授权 —— 权限判断在进程启动那一刻缓存，必须在授权之后重新打开才会生效。"
        case .denied:
            return "macOS 明确拒绝了键盘类 HID 设备的访问（kIOReturnNotPermitted）。可能是授权被撤销，也可能是重新编译后二进制变了：ad-hoc 签名下 TCC 用 cdhash 记录授权，换一次构建就对不上了。"
        case .notDetermined:
            return "这台机器的键盘背光由键盘控制器的 Aura HID 接口负责（0x0B05:0x19B6）。macOS 只允许拿到「输入监控」权限的进程打开键盘类 HID 设备。"
        case .noDevice:
            return "枚举了 IOHIDDevice 也没找到 0x0B05 的 Aura 控制器，背光通道完全不存在，跟权限无关。"
        default:
            return "ATK 设备没有 SKBV 方法（AsusSMC 报 IsKeyboardBacklightSupported=No），也没找到 Aura HID 控制器，写 LKSB 只会改影子值。"
        }
    }

    private var permissionHint: String {
        switch store.kbdPermission {
        case .busy:
            return "退出其它 天选控制中心 实例（菜单栏图标右键退出，或活动监视器里结束），再点「重新检测」。"
        case .needsRestart:
            return "点「立即重启」会自动重开本程序；之后「键盘背光」页应直接变成 0–3 档可调。"
        case .denied:
            return "顺序：打开系统设置 → 隐私与安全性 → 输入监控 → 勾选 天选控制中心；如果列表里的开关已经是开的，先点「重置授权并重新申请」再去勾选，然后重启程序。"
        case .notDetermined:
            return "点「申请权限」后系统会弹窗，勾选完必须重启程序（菜单栏图标右键 → 退出，再重新打开 App），之后这里会变成 0–3 档可调。"
        case .noDevice:
            return "可能这是 2021 年前的老机型，背光走 SMC 的 LKSB 通道；可以到「诊断」页看 AsusSMC 的 SKBV 状态。"
        default:
            return "怎么修：见「诊断」页（给 ATK 设备补 SKBV，或让 AsusSMC 改走 ASUS WMI 的 0x00050021 背光设备）。"
        }
    }

    private var channelDetail: String {
        switch store.kbdPermission {
        case .needsRestart:
            return "Aura HID 控制器已找到（0x0B05:0x19B6），授权也拿到了，只剩「重启程序」这一步 —— TCC 的判定在进程启动时读取一次，不重启就一直被拒。"
        case .denied:
            return "Aura HID 控制器已找到（0x0B05:0x19B6），但「输入监控」被拒绝；重置授权后重新勾选，再重启程序。"
        case .notDetermined:
            return "Aura HID 控制器已找到（0x0B05:0x19B6），还没有申请「输入监控」授权。"
        default:
            return store.kbdMode.detail
        }
    }

    // MARK: 通道说明

    private var channelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("当前走的是哪条通道")
                    .font(.system(size: 12.5, weight: .semibold))
                LabelValue(label: "通道", value: store.kbdMode.label, mono: true)
                LabelValue(label: "档位", value: store.kbdMaxLevel > 0 ? "0 – \(store.kbdMaxLevel)" : "—", mono: true)
                if case .hid = store.kbdMode {
                    LabelValue(label: "写入方式", value: HIDBacklight.shared.writeMethodText, mono: true)
                }
                Text(channelDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .hid = store.kbdMode {
                    Text("Aura HID 通道没有回读接口，界面上显示的档位是本程序上次成功下发的值；如果你用 Fn+F7 改了亮度，这里的数字不会跟着变。命令 asuscontrol kbd 可以查看当前通道和记录值。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                } else if case .smc = store.kbdMode {
                    Text("写入 LKSB 需要 root：AsusSMC 的 handler 会把它换算成 ACPI SKBV 的参数。首次修改会弹一次系统授权框，同一会话内后续调整不再弹。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                }
            }
        }
    }
}

