//
//  ThermalControl.swift
//  VelaX —— 三档性能模式（静音 / 平衡 / 增强）的状态中枢
//
//  优先通过 WMI 设置固件策略，需要管理员授权。DSTS 只报告能力，
//  不提供当前策略；保留本次驱动连接内成功接受的设置。
//  旧机型仍可使用 EC CMMV 回读；FX507ZM 禁止访问旧 EC/MMIO 窗口。
//

import Foundation
import Combine

/// 三档散热模式。原始值与 EC 的 CMMV 一一对应（注意不是按 UI 顺序）。
enum ThermalMode: Int, CaseIterable, Identifiable {
    case silent = 2      // 静音
    case balanced = 0    // 平衡
    case boost = 1       // 增强

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .silent:   return "静音"
        case .balanced: return "平衡"
        case .boost:    return "增强"
        }
    }

    var icon: String {
        switch self {
        case .silent:   return "leaf"
        case .balanced: return "equal"
        case .boost:    return "flame"
        }
    }

    var desc: String {
        switch self {
        case .silent:   return "风扇低速、噪音优先，长时间负载会降频"
        case .balanced: return "按负载动态调度，日常默认"
        case .boost:    return "风扇提前拉高、功耗放开"
        }
    }

    /// 命令行/配置里的名字（英文代号 + 中文 + 数字都认）
    var slug: String {
        switch self {
        case .silent:   return "silent"
        case .balanced: return "balanced"
        case .boost:    return "boost"
        }
    }

    static func parse(_ s: String) -> ThermalMode? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if let n = Int(t), let m = ThermalMode(rawValue: n) { return m }
        for m in ThermalMode.allCases {
            if t == m.slug || t == m.title { return m }
        }
        switch t {
        case "quiet", "cool", "静": return .silent
        case "normal", "standard", "auto", "性能": return .balanced
        case "turbo", "performance", "enhanced", "狂暴": return .boost
        default: return nil
        }
    }
}

@MainActor
final class ThermalControl: ObservableObject {

    static let shared = ThermalControl()

    /// 当前连接已接受的 WMI 策略，或旧机型 EC 回读值（nil = 未知）
    @Published private(set) var mode: ThermalMode?
    @Published private(set) var available = false
    /// 正在切换到哪一档（nil = 空闲）
    @Published private(set) var applying: ThermalMode?
    @Published private(set) var message: String?

    private var refreshing = false
    private var generation: UInt64 = 0

    private var allowsLegacyEC: Bool {
        let fan = FanControl.shared
        return ![fan.selectedCode, fan.detection.code].contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "FX507ZM"
        }
    }

    private init() {
        refresh()
    }

    /// 刷新不能覆盖在它之后提交的设置。
    func refresh() {
        guard !refreshing, applying == nil else { return }
        refreshing = true
        let refreshGeneration = generation
        let legacyAllowed = allowsLegacyEC
        DispatchQueue.global(qos: .utility).async {
            let wmi = ASUSWMIBridge.shared
            let av: Bool
            let raw: Int?
            if wmi.thermalDevice != nil {
                av = true
                raw = wmi.thermalMode()
            } else if legacyAllowed {
                let ec = ECFanBridge.shared
                av = ec.isAvailable
                raw = av ? ec.thermalMode() : nil
            } else {
                av = false
                raw = nil
            }
            DispatchQueue.main.async {
                self.refreshing = false
                guard refreshGeneration == self.generation, self.applying == nil else {
                    if self.applying == nil { self.refresh() }
                    return
                }
                self.available = av
                self.mode = raw.flatMap(ThermalMode.init(rawValue:))
                FanControl.shared.synchronizeFirmwarePolicy(self.mode)
            }
        }
    }

    /// WMI 以固件接受设置为准；旧 EC 路径仍验证回读。
    func set(_ target: ThermalMode) {
        guard applying == nil, FanControl.shared.applying == nil else { return }
        applying = target
        message = nil
        generation &+= 1
        let legacyAllowed = allowsLegacyEC

        DispatchQueue.global(qos: .userInitiated).async {
            let wmi = ASUSWMIBridge.shared
            let result: (ok: Bool, output: String)
            let confirmed: Bool
            let usesWMI: Bool
            if let session = wmi.thermalSessionToken {
                usesWMI = true
                result = Admin.runSelfAsAdmin(["thermal", "set", target.slug])
                // The privileged CLI is a separate process; acknowledge in the GUI's connection.
                confirmed = result.ok && wmi.recordAcceptedThermalMode(target.rawValue, session: session)
            } else if legacyAllowed {
                usesWMI = false
                let ec = ECFanBridge.shared
                result = (ok: ec.setThermalMode(target.rawValue), output: "")
                confirmed = result.ok && ec.thermalMode() == target.rawValue
            } else {
                usesWMI = true
                result = (ok: false, output: wmi.setupMessage)
                confirmed = false
            }
            DispatchQueue.main.async {
                self.applying = nil
                if confirmed {
                    self.mode = target
                    self.available = true
                    if usesWMI { FanControl.shared.noteFirmwarePolicyApplied() }
                    self.message = usesWMI
                        ? "已切到「\(target.title)」，固件已接受设置"
                        : "已切到「\(target.title)」，固件回读已确认"
                } else if result.ok {
                    self.mode = nil
                    self.message = usesWMI
                        ? "固件已接受设置，但控制驱动连接已改变，请重新设置"
                        : "写入返回成功，但固件回读不一致"
                } else {
                    self.message = result.output.isEmpty ? "性能模式设置失败：控制驱动未就绪" : result.output
                }
                self.refresh()
            }
        }
    }

    /// fan set 同时切换固件性能策略，在 GUI 连接中同步已接受的模式。
    @discardableResult
    func noteFanPresetApplied(_ name: String, session: UInt64) -> Bool {
        let target: ThermalMode
        switch name {
        case "silent": target = .silent
        case "balanced": target = .balanced
        case "performance": target = .boost
        default: return false
        }
        generation &+= 1
        let accepted = ASUSWMIBridge.shared.recordAcceptedThermalMode(target.rawValue, session: session)
        mode = accepted ? target : nil
        if accepted {
            available = true
            message = "已切到「\(target.title)」，固件已接受设置"
        } else {
            message = "控制驱动连接已改变，请重新设置"
        }
        refresh()
        return accepted
    }
}

/// 充电上限（EC 的 MB00 窗口 MBF3 = 0xF3）。
/// 0 = 不限充，其余为百分比（实测 60 / 80 / 100 可落盘）。
@MainActor
final class ChargeControl: ObservableObject {

    static let shared = ChargeControl()

    /// 当前上限（nil = 读不到；0 = 不限充）
    @Published private(set) var limit: Int?
    @Published private(set) var available = false
    @Published private(set) var applying = false
    @Published private(set) var message: String?

    private var refreshing = false

    private init() {
        refresh()
    }

    /// 常用档位
    static let presets = [60, 80, 100]

    var limitText: String {
        guard let l = limit else { return "读不到" }
        return l == 0 ? "不限充" : "\(l)%"
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let ec = ECFanBridge.shared
            let wmi = ASUSWMIBridge.shared
            let av = wmi.hasChargeLimit || ec.isAvailable
            let raw = wmi.hasChargeLimit ? wmi.chargeLimit() : (av ? ec.chargeLimit() : nil)
            DispatchQueue.main.async {
                self.available = av
                self.limit = raw
                self.refreshing = false
            }
        }
    }

    /// 设置上限。写后回读，只有回读一致才算成功。
    func set(_ pct: Int) {
        guard !applying else { return }
        applying = true
        message = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let ec = ECFanBridge.shared
            let wmi = ASUSWMIBridge.shared
            let usesWMI = wmi.hasChargeLimit
            let result = usesWMI
                ? Admin.runSelfAsAdmin(["charge", "set", String(pct)])
                : (ok: ec.setChargeLimit(pct), output: "")
            let ok = result.ok
            let readBack = usesWMI ? wmi.chargeLimit() : ec.chargeLimit()
            DispatchQueue.main.async {
                self.applying = false
                if ok, readBack == (usesWMI && pct == 0 ? 100 : pct) {
                    self.limit = pct
                    self.available = true
                    self.message = pct == 0
                        ? "已解除充电上限"
                        : "已限制到 \(pct)%，固件回读已确认"
                } else if ok {
                    self.message = "写入返回成功，但回读是 \(readBack.map(String.init) ?? "—")，可能没落盘"
                } else {
                    self.message = result.output.isEmpty ? "充电上限设置失败：控制驱动未就绪" : result.output
                }
                self.refresh()
            }
        }
    }
}
