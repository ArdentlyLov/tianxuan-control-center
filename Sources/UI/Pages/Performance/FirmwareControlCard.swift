import SwiftUI
import AppKit

/// Firmware performance policy is independent of a manual CPU wattage limit.
struct FirmwareControlCard: View {
    @ObservedObject private var thermal = ThermalControl.shared
    @ObservedObject private var charge = ChargeControl.shared
    @ObservedObject private var fan = FanControl.shared
    @State private var probing = false
    @State private var probeMessage: String?

    private func probeFirmware() {
        guard !probing else { return }
        probing = true
        probeMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let bridge = ASUSWMIBridge.shared
            let ok = bridge.probeFirmware()
            let message = ok ? "已完成只读探测；先核对读数，再测试控制功能" : (bridge.lastError ?? bridge.setupMessage)
            DispatchQueue.main.async {
                probing = false
                probeMessage = message
                fan.reloadHardwarePresets()
                thermal.refresh()
                charge.refresh()
            }
        }
    }

    var body: some View {
        if fan.selectedCode.uppercased() == "FX507ZM" || thermal.available {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "性能模式", trailing: thermal.mode?.title ?? (thermal.available ? "尚未设置" : "等待控制驱动"))
                    if !thermal.available {
                        Text(ASUSWMIBridge.shared.setupMessage)
                            .font(.system(size: 11)).foregroundStyle(Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("打开天选适配说明") {
                            if let url = Bundle.main.url(forResource: "FX507ZM-使用说明", withExtension: "txt") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(GrayButtonStyle())
                        if ASUSWMIBridge.shared.isAvailable && !ASUSWMIBridge.shared.firmwareReady {
                            Button(probing ? "读取中…" : "读取固件接口") { probeFirmware() }
                                .buttonStyle(GrayButtonStyle())
                                .disabled(probing)
                        }
                    }
                    if let message = probeMessage {
                        Text(message).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        ForEach(ThermalMode.allCases) { mode in
                            Button { thermal.set(mode) } label: {
                                Label(thermal.applying == mode ? "设置中…" : mode.title, systemImage: mode.icon)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(GrayButtonStyle(prominent: thermal.mode == mode))
                            .disabled(!thermal.available || thermal.applying != nil)
                        }
                    }
                    if let message = thermal.message {
                        Text(message).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if charge.available {
                        Divider()
                        HStack {
                            Text("充电上限：\(charge.limitText)").font(.system(size: 11))
                            Spacer()
                            ForEach(ChargeControl.presets, id: \.self) { percent in
                                Button("\(percent)%") { charge.set(percent) }
                                    .buttonStyle(GrayButtonStyle(prominent: charge.limitText == "\(percent)%"))
                                    .disabled(charge.applying)
                            }
                        }
                        if let message = charge.message {
                            Text(message).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
            .onAppear { thermal.refresh(); charge.refresh() }
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                if thermal.applying == nil { thermal.refresh() }
                if !charge.applying { charge.refresh() }
            }
        }
    }
}
