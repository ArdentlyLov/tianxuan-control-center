// MenuBarView.swift

import SwiftUI
import AppKit
import Combine

struct MenuBarMetricLabel: View {
    let item: MenuBarItem
    var iconSize: CGFloat = 9
    var valueSize: CGFloat = 11

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: item.metric.icon)
                .font(.system(size: iconSize))
            Text(item.value)
                .font(.system(size: valueSize, weight: .medium).monospacedDigit())
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var store: SensorStore

    /// 档位上限由当前通道决定：Aura HID 是 0–3，SMC(LKSB) 是 0–16，不可控时是 0。
    /// 早先这里写死成 16 档，在 HID 机型上会给出设备根本不认的档位。
    private var maxLevel: Int { store.kbdMaxLevel }

    /// 用户在「菜单栏」页勾选的监控项。菜单栏窗口每次弹出都会重建，
    /// 这里在 onAppear 里重读一次，保证改完设置立刻能看到
    @State private var metrics: [MenuMetric] = MenuBarPrefs.enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.forTemp(store.cpuTemp))
                    .frame(width: 6, height: 6)
                Text(store.hardware.modelCode.isEmpty ? "天选控制中心" : store.hardware.modelCode)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button {
                    openMainWindow(page: .menubar)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("菜单栏显示哪些项目")
            }

            Divider()

            // 勾选了哪些就显示哪些，顺序跟「菜单栏」页里的一致
            ForEach(metrics, id: \.self) { metric in
                metricRow(metric)
            }

            if metrics.isEmpty {
                Text("没有勾选任何监控项")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Button("去「菜单栏」页勾选") { openMainWindow(page: .menubar) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.accent)
            }

            Divider()

            HStack {
                Text("键盘背光")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(maxLevel > 0 ? "\(store.kbdLevel)/\(maxLevel)" : "不可控")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if maxLevel > 0 {
                backlightPicker
            } else {
                backlightUnavailable
            }

            Divider()

            HStack {
                Button("主窗口") {
                    revealMainWindow()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 236)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        // 菜单栏是临时窗口，打开时重新探一次通道，
        // 这样刚在「输入监控」里勾完授权，不必重启整个程序就能拿到新档位
        .onAppear {
            metrics = MenuBarPrefs.enabled
            store.recheckBacklightPermission()
        }
    }

    // MARK: - 监控项

    private func metricRow(_ metric: MenuMetric) -> some View {
        let value = store.menuValue(metric)
        return HStack(spacing: 6) {
            Image(systemName: metric.icon)
                .font(.system(size: 10))
                .frame(width: 13)
                .foregroundStyle(value.available ? Palette.accent : Palette.textTertiary)
            Text(metric.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value.text)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(value.available ? Color.primary : Palette.textTertiary)
                .help(value.reason ?? "")
        }
    }

    /// 打开主窗口并（可选）切到指定页。
    /// 不再依赖 SwiftUI 的 openWindow 环境（弹窗由 NSPopover 承载，拿不到该环境值），
    /// 直接按 identifier 找到主窗口并前置。
    private func openMainWindow(page: Page) {
        revealMainWindow(setPage: page)
    }

    private func revealMainWindow(setPage page: Page? = nil) {
        if let page { PageRouter.shared.jump(to: page) }
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            w.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 背光档位

    @ViewBuilder
    private var backlightPicker: some View {
        if maxLevel <= 8 {
            // 档位少（HID 通道 0–3）：直接给离散按钮，点哪个就是哪个
            HStack(spacing: 4) {
                ForEach(0...maxLevel, id: \.self) { lv in
                    levelButton(lv)
                }
            }
        } else {
            // 档位多（SMC 通道 0–16）：17 个按钮挤不下，改用连续条 + 一个「关」
            HStack(spacing: 6) {
                levelButton(0)
                    .frame(width: 30)
                LevelDots(level: store.kbdLevel, maxLevel: maxLevel) {
                    store.setKeyboardBacklight($0)
                }
                .frame(maxWidth: .infinity, maxHeight: 18)
            }
        }
    }

    private func levelButton(_ lv: Int) -> some View {
        Button {
            store.setKeyboardBacklight(lv)
        } label: {
            Text(lv == 0 ? "关" : "\(lv)")
                .font(.system(size: 10).monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: Palette.cornerRadius)
                        .fill(store.kbdLevel == lv ? Palette.accent.opacity(0.85) : Color.primary.opacity(0.07))
                )
                .foregroundStyle(store.kbdLevel == lv ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.kbdBusy)
    }

    /// 通道不可用 / 还没授权时的引导，文案与「键盘背光」页保持一致
    private var backlightUnavailable: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(unavailableText)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                revealMainWindow()
            } label: {
                Text("去主窗口处理")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var unavailableText: String {
        switch store.kbdPermission {
        case .granted:       return "背光通道探测中…"
        case .denied:        return "「输入监控」被拒绝，需在系统设置里重新勾选"
        case .needsRestart:  return "已授权，重启程序后生效"
        case .notDetermined: return "尚未获得「输入监控」授权"
        case .busy:          return "键盘设备被其它进程占用"
        case .noDevice:      return "未找到 Aura HID 控制器"
        }
    }
}

