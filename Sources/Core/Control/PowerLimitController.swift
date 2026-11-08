// PowerLimitController.swift

import Foundation
import Combine

// MARK: - 控制器

@MainActor
final class PowerLimitController: ObservableObject {
    static let shared = PowerLimitController()

    @Published private(set) var profile: PowerProfile = .balanced
    @Published private(set) var customWatts: Int = 30
    /// 已下发的瓦数；nil = 未限制（默认功耗墙）
    @Published private(set) var appliedWatts: Int?
    @Published private(set) var applying = false
    @Published private(set) var message: String?
    /// 功能解锁开关：默认关，需在「高级功能」页确认风险后解锁
    @Published private(set) var unlocked: Bool
    /// 当前走哪条通道（检测一次后缓存，刷新时重测）
    @Published private(set) var backend: PowerBackend = .none
    /// RAPL 通道下从 MSR 读到的硬件值（SMC 通道下为 nil）
    @Published private(set) var hardwarePL1: Int?
    @Published private(set) var hardwarePL2: Int?
    /// RAPL 的 lock 位（true = 硬件会忽略写入，只能进 BIOS 改）
    @Published private(set) var lockedByFirmware = false

    /// 「登录时自动下发」（LaunchAgent）：重启后固件会重编程回标称值，靠它把档位找回来
    @Published private(set) var persistEnabled: Bool
    /// 本机实测满载功耗（W）；nil = 没测过。和寄存器里的标称值完全是两回事。
    @Published private(set) var measuredCeiling: Int?
    @Published private(set) var measuredAt: Date?
    @Published private(set) var measuring = false

    private init() {
        unlocked = Prefs.bool(PowerLimitSpec.prefsUnlocked)
        backend = PowerWallProbe.backend
        persistEnabled = PowerWallPersist.isEnabled
        let measured = Prefs.int(PowerLimitSpec.prefsMeasured, default: 0)
        measuredCeiling = measured > 0 ? measured : nil
        let at = Prefs.int(PowerLimitSpec.prefsMeasuredAt, default: 0)
        measuredAt = at > 0 ? Date(timeIntervalSince1970: TimeInterval(at)) : nil
        if let raw = Prefs.string(PowerLimitSpec.prefsProfile),
           let p = PowerProfile(rawValue: raw) {
            profile = p
        }
        if let w = Prefs.string(PowerLimitSpec.prefsCustom), let v = Int(w) {
            customWatts = clamped(v)
        }
    }

    /// 从硬件回读当前功耗墙
    /// 注意：SMC 通道只反映「最后一次写入的值」，不代表 EC 当前真实墙值；
    /// RAPL 通道读到的是 CPU 寄存器里的真实值。
    func refreshApplied() {
        let detected = Self.detectBackend()
        backend = detected
        persistEnabled = PowerWallPersist.isEnabled
        let measured = Prefs.int(PowerLimitSpec.prefsMeasured, default: 0)
        measuredCeiling = measured > 0 ? measured : nil
        let at = Prefs.int(PowerLimitSpec.prefsMeasuredAt, default: 0)
        measuredAt = at > 0 ? Date(timeIntervalSince1970: TimeInterval(at)) : nil

        switch detected {
        case .smc:
            hardwarePL1 = nil
            hardwarePL2 = nil
            lockedByFirmware = false
            if let v = try? SMCClient.shared.readUInt8(PowerLimitSpec.keyWatts), v > 0 {
                appliedWatts = Int(v)
            } else {
                appliedWatts = nil
            }
        case .rapl:
            if let r = RAPLBridge.shared.reading() {
                hardwarePL1 = Int(r.pl1W.rounded())
                hardwarePL2 = Int(r.pl2W.rounded())
                lockedByFirmware = r.locked
                // 只有我们自己下发过（存了原始值）才显示「已限 XXW」，
                // 否则那只是出厂墙，写成「已限」会误导
                appliedWatts = RAPLBridge.shared.hasOriginal ? Int(r.pl1W.rounded()) : nil
            } else {
                hardwarePL1 = nil
                hardwarePL2 = nil
            }
        case .none:
            hardwarePL1 = nil
            hardwarePL2 = nil
            lockedByFirmware = false
            appliedWatts = nil
        }
    }

    /// 通道探测：SMC 键优先（那是原设计的主线），其次 RAPL（Intel 机型）
    static func detectBackend() -> PowerBackend { PowerWallProbe.backend }

    /// 当前通道是否可用（历史名字，UI 与能力矩阵都在用）
    var kextSupported: Bool { backend != .none }

    func clamped(_ w: Int) -> Int {
        min(max(w, PowerLimitSpec.minW), PowerLimitSpec.maxW)
    }

    func select(_ p: PowerProfile) {
        // 三档预设随时可用；只有「自定义」受高级功能的解锁门约束
        if p == .custom && !unlocked {
            requestCustom()
            return
        }
        profile = p
        Prefs.set(p.rawValue, for: PowerLimitSpec.prefsProfile)
    }

    /// 点「自定义」档位：未解锁时不切换，只提示去「高级功能」解锁
    func requestCustom() {
        if unlocked {
            select(.custom)
            return
        }
        message = "自定义功耗档未解锁：请在「高级功能」页打开「自定义功耗墙」开关并确认风险"
    }

    func setCustom(_ w: Int) {
        customWatts = clamped(w)
        Prefs.set(String(customWatts), for: PowerLimitSpec.prefsCustom)
    }

    /// 高级功能页确认风险后解锁 / 关闭
    func unlock() {
        unlocked = true
        Prefs.set(true, for: PowerLimitSpec.prefsUnlocked)
    }

    func lock() {
        unlocked = false
        Prefs.set(false, for: PowerLimitSpec.prefsUnlocked)
        // 上锁时若正停在「自定义」，退回平衡档，避免留一个用不了的档位
        if profile == .custom {
            profile = .balanced
            Prefs.set(profile.rawValue, for: PowerLimitSpec.prefsProfile)
        }
        message = nil
    }

    /// 当前档位对应的瓦数
    var targetWatts: Int {
        profile.watts ?? customWatts
    }

    /// 下发当前档位
    func apply() {
        let w = targetWatts
        guard profile != .custom || unlocked else {
            message = "自定义功耗档未解锁：请在「高级功能」页打开「自定义功耗墙」开关并确认风险"
            return
        }
        guard !applying else { return }

        switch backend {
        case .smc:
            applyViaSMC(w)
        case .rapl:
            applyViaRAPL(w)
        case .none:
            message = "没有可用的功耗墙通道：SMC 的 AFsC / AFsw 不存在，AsusECTool.kext 也没有 MSR 通道（需要 v1.4.0 及以上）"
        }
    }

    /// SMC 通道：写 AFsC / AFsw，需要管理员授权（走自己的 CLI）
    private func applyViaSMC(_ w: Int) {
        applying = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Admin.runSelfAsAdmin(["fan", "power-limit", String(w)])
            DispatchQueue.main.async {
                self.applying = false
                if result.ok {
                    self.appliedWatts = w
                    self.message = "已设为 \(w)W，功耗通常 1–2 秒内跟上"
                } else {
                    let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.message = text.isEmpty ? "下发失败（未拿到输出）" : text
                }
            }
        }
    }

    /// RAPL 通道：kext 直接写 MSR 0x610，不需要提权
    private func applyViaRAPL(_ w: Int) {
        applying = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            // PL1 与 PL2 一起压：只压长期墙的话，爆发期仍会按 PL2 放行
            let r = RAPLBridge.shared.setLimits(pl1: w, pl2: w)
            DispatchQueue.main.async {
                self.applying = false
                switch r {
                case .success(let actual):
                    self.appliedWatts = actual
                    self.hardwarePL1 = actual
                    self.hardwarePL2 = RAPLBridge.shared.reading().map { Int($0.pl2W.rounded()) }
                    self.lockedByFirmware = false
                    // 记下目标瓦数：重启后由 LaunchAgent（或下次启动） replay 回来
                    PowerWallPersist.noteApplied(actual)
                    self.message = actual == w
                        ? "已设为 \(w)W（PL1 + PL2 一起压），跑 1–2 秒负载看功耗曲线是否被按住"
                        : "已写入 \(w)W，硬件回读为 \(actual)W（刻度取整，误差 ±1W 属正常）"
                case .failure(let e):
                    self.message = e.description
                    self.lockedByFirmware = (e == .locked)
                    self.refreshApplied()
                }
            }
        }
    }

    /// 恢复默认（AFsw = 0 → 回到 EC 当前 PL1；RAPL → 写回第一次读到的原始值）
    func restore() {
        guard !applying else { return }

        switch backend {
        case .smc:
            applying = true
            message = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Admin.runSelfAsAdmin(["fan", "power-limit", "0"])
                DispatchQueue.main.async {
                    self.applying = false
                    if result.ok {
                        self.appliedWatts = nil
                        PowerWallPersist.clearTarget()
                        self.message = "已恢复默认功耗墙"
                    } else {
                        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.message = text.isEmpty ? "恢复失败（未拿到输出）" : text
                    }
                }
            }
        case .rapl:
            guard RAPLBridge.shared.hasOriginal else {
                message = "没有存过的原始功耗墙可恢复（本程序还没下发过）"
                return
            }
            applying = true
            message = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let r = RAPLBridge.shared.restoreOriginal()
                DispatchQueue.main.async {
                    self.applying = false
                    switch r {
                    case .success(let w):
                        self.appliedWatts = nil
                        // 没限制就没有「重启后要恢复的东西」了，避免登录时白写一次
                        PowerWallPersist.clearTarget()
                        self.message = "已恢复出厂功耗墙（回读 PL1 = \(w)W）"
                        self.refreshApplied()
                    case .failure(let e):
                        self.message = e.description
                    }
                }
            }
        case .none:
            message = "没有可用的功耗墙通道"
        }
    }

    // MARK: - 登录自动下发

    /// 打开 / 关闭「登录时自动保持」
    func setPersist(_ on: Bool) {
        if let err = PowerWallPersist.set(on) {
            message = err
            persistEnabled = PowerWallPersist.isEnabled
            return
        }
        persistEnabled = PowerWallPersist.isEnabled
        message = on
            ? (appliedWatts == nil
               ? "已开启。当前没设限，等你应用某个瓦数后，登录时才会自动写回"
               : "已开启。下次登录会自动写回 \(appliedWatts!)W（重启后固件会先把它冲回标称值）")
            : "已关闭登录自动下发，重启后回到标称功耗墙"
    }

    /// App 启动 / 唤醒时补一次（不依赖 LaunchAgent 是否装了）
    func replayOnLaunch() {
        guard backend == .rapl, PowerWallPersist.target != nil else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let w = PowerWallPersist.replay() else { return }
            DispatchQueue.main.async {
                self.appliedWatts = w
                self.hardwarePL1 = w
                self.message = "已按上次的档位恢复 \(w)W"
                self.refreshApplied()
            }
        }
    }

    // MARK: - 实测本机上限

    /// 造一段满载，用 MSR 0x611 的能量差算出真能吃多少瓦。
    /// 必须在「未限制」状态下测，否则量到的是你自己设的墙。
    func measureCeiling() {
        guard backend == .rapl else {
            message = "只有 RAPL 通道能实测（SMC 通道读不到封装功耗）"
            return
        }
        guard !applying, !measuring else { return }
        if appliedWatts != nil {
            message = "先点「恢复默认」再实测，否则量到的是你设的墙"
            return
        }
        measuring = true
        message = nil

        DispatchQueue.global(qos: .userInitiated).async {
            var best: Double = 0
            // 跑两轮取较大值：单次 0.2s 窗口的 MSR 采样有 ±5W 抖动
            for _ in 0..<2 {
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .userInitiated).async {
                    PowerBench.burn(seconds: 4.0)
                    done.signal()
                }
                // 等负载真正压上来再开采样窗，否则会摊掉开头那段爬坡
                Thread.sleep(forTimeInterval: 1.0)
                if let w = RAPLBridge.shared.packageWatts(window: 2.5) {
                    best = max(best, w)
                }
                done.wait()
            }
            let watts = Int(best.rounded())
            DispatchQueue.main.async {
                self.measuring = false
                guard watts > 0 else {
                    self.message = "实测失败：读不到 MSR 0x611 的能量计数"
                    return
                }
                self.measuredCeiling = watts
                self.measuredAt = Date()
                Prefs.set(watts, for: PowerLimitSpec.prefsMeasured)
                Prefs.set(Int(Date().timeIntervalSince1970), for: PowerLimitSpec.prefsMeasuredAt)
                self.message = "实测满载约 \(watts)W（两轮取较大值）"
            }
        }
    }
}

