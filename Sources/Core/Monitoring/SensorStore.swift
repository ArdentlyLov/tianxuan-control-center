//
//  SensorStore.swift
//  采样引擎 + 状态中枢
//
//  线程模型：
//    · 采样队列（串行，.utility）负责所有 IOKit / libproc / Mach 调用
//    · 主线程只做「把一次采样结果写回 @Published」，不碰任何系统调用
//
//  为什么这样改：Control.currentLevel() 每次要枚举全部 IOHID 设备并尝试 open，
//  单次 13 ms（峰值 21 ms），原来每秒在主线程跑一次，必然每秒掉一帧。
//  现在这类调用要么被缓存，要么移到后台队列，主线程一轮只剩微秒级赋值。
//

import Foundation
import Combine

/// 一次采样的不可变结果（后台队列生产，主线程消费）
struct SampleFrame {
    var seq: Int = 0
    var at = Date()
    var temp: Double?
    var load = SystemLoadSnapshot()
    var battery: BatteryInfo?
    var tiles: [String: SMCReading]?
    var processes: [ProcSample]?
    var net = NetSpeedSnapshot()
    var gpuUsage: Double?
    var gpuTemp: Double?
    var gpuName: String?
    var gpuFrequencyMHz: Double?
    var powerWatts: Double?
    /// 显卡功耗（W），来自当前 GPU 驱动；nil = 未提供有效读数
    var gpuPowerWatts: Double?
    /// 显卡强制功耗上限（W）
    var gpuPowerLimitWatts: Double?
    /// 已用显存 / 显存总量（MiB）
    var vramUsedMB: Double?
    var vramTotalMB: Double?
    /// CPU 实时频率（GHz），来自 Intel / AMD 监测接口；nil = 没采到
    var cpuFreqGHz: Double?
    var cpuMaxFreqGHz: Double?
    var disk: DiskInfo?
}

final class SensorStore: ObservableObject {
    static let shared = SensorStore()

    // 硬件 / 静态信息
    @Published var hardware = HardwareInfo()
    @Published var battery = BatteryInfo()
    @Published var disk = DiskInfo()
    @Published var kexts = KextState()
    @Published var capabilities: [Capability] = []

    // 采样数据（后台产出 → 主线程批量写入）
    //
    // 这些字段故意不用 @Published：一轮采样会同时改十几个值，
    // 每个 @Published 各发一次 objectWillChange，SwiftUI 就会把整页重排十几遍
    // （实测每帧 ~190 ms CPU）。改成普通属性 + 帧首手动发一次通知。
    private(set) var cpuTemp: Double?
    private(set) var tempHistory: [Double] = []
    private(set) var freqHistory: [Double] = []
    private(set) var cpuMaxFreqGHz: Double?
    var cpuFrequencyDetail: String {
        if let peak = cpuMaxFreqGHz { return String(format: "本次最高核心 %.2f GHz", peak) }
        return cpuFreq.liveGHz == nil ? "等待实时频率采样…" : "全核心平均有效频率"
    }
    private(set) var powerHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var gpuPowerHistory: [Double] = []
    private(set) var gpuFrequencyHistory: [Double] = []
    /// 整机功耗（CPU 整包 + GPU）的历史；缺一路时按可用的一路记
    private(set) var systemPowerHistory: [Double] = []
    private(set) var vramHistory: [Double] = []
    private(set) var fanRPM: Double?
    private(set) var fanRPMGPU: Double?
    private(set) var fanRPMCenter: Double?
    private(set) var fanCount = 0
    private(set) var fanAvailable = false
    private(set) var fanSource = "不可用"
    private(set) var fanUnavailableReason = "等待风扇采样…"
    private(set) var gpuTemp: Double?
    private(set) var gpuName: String?
    private(set) var gpuFrequencyMHz: Double?
    private(set) var load = SystemLoadSnapshot()
    private(set) var loadHistory: [Double] = []
    private(set) var tiles: [String: SMCReading] = [:]
    private(set) var sampleCount = 0
    private(set) var lastUpdate = Date()

    // 菜单栏可选项（见 MenuMetrics.swift）
    //
    // GPU 各指标每帧从同一设备采样；不以启动时的可用性锁住后续采样。
    private(set) var netSpeed = NetSpeedSnapshot()
    /// 上传 / 下载累计字节数 = 内核计数器的值 − 基线（见 `NetTotals`）
    private(set) var netTotalDown: Double = 0
    private(set) var netTotalUp: Double = 0
    private(set) var netTotalsSince = Date()
    private(set) var gpuUsage: Double?
    private(set) var powerWatts: Double?
    /// 显卡功耗（W），显存占用使用 MiB；支持原生驱动与可选 NVIDIA sysctl。
    private(set) var gpuPowerWatts: Double?

    /// 整机功耗估算 = CPU 整包 + GPU（两项都得自行注入，macOS 没有系统级功耗接口）。
    /// 只有一路可用时退化为该路的值，UI 会在副标题里说明「仅 CPU / 仅 GPU」。
    var systemPowerWatts: Double? {
        switch (powerWatts, gpuPowerWatts) {
        case let (cpu?, gpu?): return cpu + gpu
        case let (cpu?, nil):  return cpu
        case let (nil, gpu?):  return gpu
        default: return nil
        }
    }
    private(set) var gpuPowerLimitWatts: Double?
    private(set) var vramUsedMB: Double?
    private(set) var vramTotalMB: Double?
    private(set) var cpuFreq = CPUFrequencyInfo()

    // 应用级监控
    private(set) var processes: [ProcSample] = []
    private(set) var history: [MetricSample] = []

    // 录制
    private(set) var recording: ActiveRecording?
    @Published var recordings: [RecordingSummary] = []
    private(set) var recordingTick: Int = 0          // 仅用于驱动界面刷新计时

    // 键盘背光
    @Published var kbdLevel: Int = 0
    @Published var kbdMaxLevel: Int = 0
    @Published var kbdMode: BacklightMode = .none
    @Published var kbdPermission: HIDBacklight.PermissionState = .notDetermined
    @Published var kbdBlockedByPermission = false
    @Published var kbdAvailable = false
    @Published var kbdBusy = false
    @Published var kbdError: String?
    @Published var kbdAssumed = false   // 授权期间乐观显示

    // NVIDIA（NullMoth）驱动更新
    @Published private(set) var nvidiaUpdate: NvidiaUpdateState = .unknown
    @Published private(set) var nvidiaRelease: NvidiaRelease?

    // 全键表
    @Published var readings: [SMCReading] = []
    @Published var keyNames: [String] = []
    @Published var smcReady = false

    /// 采样间隔（改动会立即重建定时器并持久化）
    @Published private(set) var samplingRate: SamplingRate = .saved

    // MARK: 采样线程私有状态（只在 sampleQueue 上访问）

    private struct SamplerConfig {
        var interval: TimeInterval = 2
        var batteryPeriod: TimeInterval = 15
        var diskPeriod: TimeInterval = 15
        var processPeriod: TimeInterval = 2
        var wantTiles = false
        var pageProcesses = false
        var recordingPID: Int32?

        var wantProcesses: Bool { pageProcesses || recordingPID != nil }
    }

    private let sampleQueue = DispatchQueue(label: "dev.vela.sampler", qos: .utility)
    private let fanQueue = DispatchQueue(label: "dev.vela.fans", qos: .userInitiated)
    private var sensorTimer: DispatchSourceTimer?
    private var fanTimer: DispatchSourceTimer?
    private var config = SamplerConfig()
    private var seq = 0
    private var lastBattery = Date.distantPast
    private var lastDisk = Date.distantPast
    private var lastProcess = Date.distantPast
    private var collecting = false

    private var kbdDebounce: Timer?
    private var pendingKbd: Int?

    private init() {}

    // MARK: - 生命周期

    func start() {
        guard sensorTimer == nil else { return }
        smcReady = SMC.available
        loadStaticInfo()
        recordings = RecordingStore.loadIndex()
        restartTimer()
        nvidiaUpdate = NvidiaUpdate.stateFromCache()
        nvidiaRelease = NvidiaUpdate.cachedRelease
        if NvidiaUpdate.needsAutoCheck { checkNvidiaUpdate() }
    }

    /// 快照 / 自检用：临时提高采样率但不写入偏好
    func overrideRate(_ rate: SamplingRate) {
        guard rate != samplingRate else { return }
        samplingRate = rate
        restartTimer()
    }

    func setSamplingRate(_ rate: SamplingRate) {
        guard rate != samplingRate else { return }
        samplingRate = rate
        rate.persist()
        trimHistory()
        restartTimer()
    }

    private func restartTimer() {
        let seconds = samplingRate.rawValue
        let rate = samplingRate
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.config.interval = TimeInterval(seconds)
            self.config.batteryPeriod = rate.batteryPeriod
            self.config.diskPeriod = rate.batteryPeriod
            self.config.processPeriod = rate.processPeriod
            self.sensorTimer?.cancel()

            let timer = DispatchSource.makeTimerSource(queue: self.sampleQueue)
            timer.schedule(deadline: .now() + 0.05,
                           repeating: .milliseconds(seconds * 1000),
                           leeway: .milliseconds(seconds >= 3 ? 400 : 120))
            timer.setEventHandler { [weak self] in self?.collect() }
            timer.resume()
            self.sensorTimer = timer

            // 风扇反馈固定每半秒采样，不受温度/历史曲线的采样偏好影响。
            if self.fanTimer == nil {
                // 单独队列，进程列表和完整传感器读取不能拖慢转速反馈。
                let fans = DispatchSource.makeTimerSource(queue: self.fanQueue)
                fans.schedule(deadline: .now(), repeating: .milliseconds(500),
                              leeway: .milliseconds(25))
                fans.setEventHandler { [weak self] in self?.collectFans() }
                fans.resume()
                self.fanTimer = fans
            }
        }
    }

    private func trimHistory() {
        let tempCap = samplingRate.tempCapacity
        if tempHistory.count > tempCap { tempHistory.removeFirst(tempHistory.count - tempCap) }
        if loadHistory.count > tempCap { loadHistory.removeFirst(loadHistory.count - tempCap) }
        if freqHistory.count > tempCap { freqHistory.removeFirst(freqHistory.count - tempCap) }
        if powerHistory.count > tempCap { powerHistory.removeFirst(powerHistory.count - tempCap) }
        if gpuHistory.count > tempCap { gpuHistory.removeFirst(gpuHistory.count - tempCap) }
        if gpuPowerHistory.count > tempCap { gpuPowerHistory.removeFirst(gpuPowerHistory.count - tempCap) }
        if gpuFrequencyHistory.count > tempCap { gpuFrequencyHistory.removeFirst(gpuFrequencyHistory.count - tempCap) }
        if vramHistory.count > tempCap { vramHistory.removeFirst(vramHistory.count - tempCap) }
        let histCap = samplingRate.historyCapacity
        if history.count > histCap { history.removeFirst(history.count - histCap) }
    }

    /// 清零网络累计（「网络」页的「重置统计」）
    func resetNetTotals() {
        // 不是把内存里的数归零（那样重启 App 又会涨回内核计数器的值），
        // 而是把「基线」推进到计数器此刻的值 —— 之后总量 = 系统计数 − 基线，从现在重新算。
        netBase.down = netSpeed.totalDown
        netBase.up = netSpeed.totalUp
        netBase.boot = netSpeed.bootTime
        netSince = Date().timeIntervalSince1970
        netTotalDown = 0
        netTotalUp = 0
        netTotalsSince = Date(timeIntervalSince1970: netSince)
        netBase.save(since: netSince)
    }

    // MARK: - 网络总量（跟随系统计数器）

    /// 网络累计的持久化基线。
    ///
    /// 以前总量是拿「瞬时速率 × 采样间隔」积分出来的：App 一退就没了，重启又从 0 开始，
    /// 和系统的统计对不上。现在直接读内核的 64 位网卡计数器（自开机累计），
    /// 只在 Prefs 里存一个「从哪儿开始算」的基线：
    ///   总量 = 系统计数 − 基线
    /// 基线持久保存，所以重启 App 不会重新计算；只有重启系统（计数器归零）
    /// 或用户点「重置统计」才会换基线。
    private struct NetTotals {
        var down: UInt64 = 0
        var up: UInt64 = 0
        /// 存基线时那次开机的时刻，用来发现「系统已经重启过 → 计数器归零 → 基线作废」
        var boot: TimeInterval = 0

        private static let downKey = "net.base.down"
        private static let upKey = "net.base.up"
        private static let bootKey = "net.base.boot"
        private static let sinceKey = "net.since"

        static func load() -> NetTotals {
            NetTotals(down: UInt64(Prefs.string(downKey) ?? "") ?? 0,
                      up: UInt64(Prefs.string(upKey) ?? "") ?? 0,
                      boot: Double(Prefs.string(bootKey) ?? "") ?? 0)
        }

        func save(since: TimeInterval) {
            Prefs.set(String(down), for: NetTotals.downKey)
            Prefs.set(String(up), for: NetTotals.upKey)
            Prefs.set(String(Int64(boot)), for: NetTotals.bootKey)
            Prefs.set(String(Int64(since)), for: NetTotals.sinceKey)
        }

        static func savedSince() -> TimeInterval {
            Double(Prefs.string(sinceKey) ?? "") ?? 0
        }
    }

    private var netBase = NetTotals.load()
    private var netSince: TimeInterval = NetTotals.savedSince()

    /// 每个采样点用内核计数器刷新总量；系统重启过就自动重新起算
    private func updateNetTotals(_ snap: NetSpeedSnapshot) {
        let boot = snap.bootTime
        if boot > 0, abs(boot - netBase.boot) > 2 {
            // 系统重启过（或首次运行）：计数器已归零，基线作废，从这次开机重新累计
            netBase = NetTotals(down: 0, up: 0, boot: boot)
            netSince = boot
            netBase.save(since: netSince)
        }
        netTotalDown = Double(snap.totalDown >= netBase.down ? snap.totalDown - netBase.down : 0)
        netTotalUp = Double(snap.totalUp >= netBase.up ? snap.totalUp - netBase.up : 0)
        if netSince > 0 { netTotalsSince = Date(timeIntervalSince1970: netSince) }
    }

    private func loadStaticInfo() {
        let store = self
        DispatchQueue.global(qos: .userInitiated).async {
            let hw = SystemProbe.hardware()
            let kext = SystemProbe.kexts()
            let bat = SystemProbe.battery()
            let caps = Capabilities.all(gpus: hw.gpus)
            let names = SMC.allKeys()
            // CPU 标称频率是静态信息；GPU 可用性每帧重新判断。
            MetricProbe.shared.probeIfNeeded()
            let freq = MetricProbe.shared.cpuFreq
            DispatchQueue.main.async {
                store.hardware = hw
                store.kexts = kext
                store.battery = bat
                store.capabilities = caps
                store.keyNames = names
                store.cpuFreq.nominalHz = freq.nominalHz
                // 实时 CPU 数据每帧由 Intel / AMD 监测接口填充。
                let mode = Control.mode
                store.kbdMode = mode
                store.kbdMaxLevel = mode.maxLevel
                store.kbdAvailable = mode.maxLevel > 0
                store.kbdPermission = Control.permissionState
                store.kbdBlockedByPermission = Control.hidBlocked
                store.kbdLevel = Control.currentLevel()
                store.maybeRequestHIDPermission()
            }
        }
    }

    /// 首次发现「Aura HID 被系统拦截」时申请一次输入监控权限，
    /// 这样程序才会被登记进 系统设置 → 隐私与安全性 → 输入监控 的列表里
    private func maybeRequestHIDPermission() {
        guard Control.hidBlocked,
              HIDBacklight.listenPermission == .unknown else { return }
        let key = "hid.permissionAsked"
        if Prefs.bool(key) { return }
        Prefs.set(true, for: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            _ = HIDBacklight.requestPermission()
        }
    }

    // MARK: - 采集（后台队列）

    private func collectFans() {
        let snapshot = FanProbe.sample()
        let reason = snapshot.isAvailable ? "" : FanProbe.unavailableReason
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.fanRPM != snapshot.cpuRPM || self.fanRPMGPU != snapshot.gpuRPM ||
                  self.fanRPMCenter != snapshot.centerRPM ||
                  self.fanCount != snapshot.count || self.fanAvailable != snapshot.isAvailable ||
                  self.fanSource != snapshot.backendLabel || self.fanUnavailableReason != reason else { return }
            self.objectWillChange.send()
            self.fanRPM = snapshot.cpuRPM
            self.fanRPMGPU = snapshot.gpuRPM
            self.fanRPMCenter = snapshot.centerRPM
            self.fanCount = snapshot.count
            self.fanAvailable = snapshot.isAvailable
            self.fanSource = snapshot.backendLabel
            self.fanUnavailableReason = reason
        }
    }

    private func collect() {
        guard !collecting else { return }
        collecting = true
        defer { collecting = false }

        seq += 1
        var frame = SampleFrame(seq: seq, at: Date())

        frame.temp = CPUTemperatureProbe.readSMC()

        frame.load = SystemLoad.sample()
        frame.net = NetSpeed.sample()

        let g = GPUProbe.stats()
        frame.gpuName = g.name == "GPU" ? nil : g.name
        frame.gpuUsage = g.usage
        frame.gpuTemp = g.temperature
        frame.gpuPowerWatts = g.powerWatts
        frame.gpuPowerLimitWatts = g.limitWatts
        frame.gpuFrequencyMHz = g.frequencyMHz
        frame.vramUsedMB = g.vramUsedMB
        frame.vramTotalMB = g.vramTotalMB
        // Intel EnergyDriver / AMD 用户客户端均可在普通用户态采样。
        if IntelPowerProbe.shared.available {
            let s = IntelPowerProbe.shared.sample()
            frame.temp = s.temperature ?? frame.temp
            frame.powerWatts = s.powerWatts
            frame.cpuFreqGHz = s.avgFreqGHz
            frame.cpuMaxFreqGHz = s.maxFreqGHz
        } else if MetricProbe.shared.amdAvailable {
            let s = AMDRyzenProbe.shared.sample()
            frame.powerWatts = s.powerWatts
            frame.cpuFreqGHz = s.avgFreqGHz
            frame.cpuMaxFreqGHz = s.maxFreqGHz
        }

        if config.wantTiles {
            var dict: [String: SMCReading] = [:]
            dict.reserveCapacity(SMCKeyCatalog.interesting.count)
            for meta in SMCKeyCatalog.interesting {
                if let r = SMC.read(meta.key) { dict[meta.key] = r }
            }
            frame.tiles = dict
        }

        if frame.at.timeIntervalSince(lastBattery) >= config.batteryPeriod {
            lastBattery = frame.at
            frame.battery = SystemProbe.battery()
        }

        if frame.at.timeIntervalSince(lastDisk) >= config.diskPeriod {
            lastDisk = frame.at
            frame.disk = DiskInfo.current()
        }

        if config.wantProcesses,
           frame.at.timeIntervalSince(lastProcess) >= config.processPeriod {
            lastProcess = frame.at
            frame.processes = ProcessSampler.sample()
        }

        DispatchQueue.main.async { [weak self] in self?.apply(frame) }
    }

    /// 上一轮推给界面的「可见值签名」。0 表示还没推过，第一帧必须放行。
    private var lastVisibleSignature: UInt64 = 0

    /// 把这一帧里「会改变像素」的量按显示精度抹零后揉成一个整数（FNV-1a）。
    /// 只取界面上真的会显示、且精度有限的项：温度 0.1 °C、负载 0.5%、网速 0.5 KB/s……
    /// 传感器页（tiles）和监控页（processes）要逐项刷新，有这两类数据不做合并。
    private func visibleSignature(_ frame: SampleFrame) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x0000_0100_0000_01b3 }
        func mixRounded(_ v: Double?, _ scale: Double) {
            guard let v else { mix(0xFFFF_FFFF); return }
            mix(UInt64(bitPattern: Int64((v * scale).rounded())))
        }

        mixRounded(frame.temp, 10)              // 0.1 °C
        mixRounded(frame.load.total, 500)       // 0.5 %
        mixRounded(frame.load.memoryUsedRatio, 500)
        mixRounded(frame.load.swapUsed > 0 ? Double(frame.load.swapUsed) / 1e6 : nil, 10)
        mixRounded(frame.gpuUsage, 1)
        mixRounded(frame.gpuTemp, 1)
        mixRounded(frame.gpuFrequencyMHz, 1)
        mixRounded(frame.gpuPowerLimitWatts, 10)
        mixRounded(frame.vramTotalMB, 1)
        for byte in (frame.gpuName ?? "").utf8 { mix(UInt64(byte)) }
        mixRounded(frame.powerWatts, 1)
        mixRounded(frame.gpuPowerWatts, 10)       // 0.1 W
        mixRounded(frame.vramUsedMB, 1)           // 1 MB
        mixRounded(frame.cpuFreqGHz, 100)     // 0.01 GHz
        mixRounded(frame.cpuMaxFreqGHz, 100)
        mixRounded(frame.net.down, 2)           // 0.5 KB/s
        mixRounded(frame.net.up, 2)
        mix(UInt64(frame.load.perCore.count))
        for core in frame.load.perCore.prefix(32) { mixRounded(core, 100) }
        if let b = frame.battery {
            mix(UInt64(bitPattern: Int64(b.charge)))
            mix(b.charging ? 1 : 2)
            mix(b.externalPower ? 3 : 4)
        }
        if let d = frame.disk {
            mix(UInt64(bitPattern: d.usedBytes))
            mix(UInt64(d.totalBytes))
        }
        if frame.tiles != nil { mix(0xA11CE) }
        if frame.processes != nil { mix(0xBEEF) }
        return h
    }

    private func apply(_ frame: SampleFrame) {
        // 一整帧只通知一次，避免十几次重排；
        // 而且「值没变就不通知」—— 采样间隔 1 秒时，温度、负载、内存大多只是
        // 在小数点后抖动，四舍五入到显示精度后屏幕上一个像素都不会变，
        // 却要重绘整窗玻璃 + 十几张卡片。签名相同就直接跳过，空闲时 CPU 归零。
        let signature = visibleSignature(frame)
        // 每 10 帧兜底放行一次：界面上的「采样点 / 时间戳」这类派生信息偶尔要靠
        // 刷新才会动，不能让它们长时间停住。
        let changed = signature != lastVisibleSignature || sampleCount % 10 == 0
        lastVisibleSignature = signature
        if changed { objectWillChange.send() }

        if let t = frame.temp {
            cpuTemp = t
            tempHistory.append(t)
            let cap = samplingRate.tempCapacity
            if tempHistory.count > cap { tempHistory.removeFirst(tempHistory.count - cap) }
        }

        load = frame.load
        netSpeed = frame.net
        updateNetTotals(frame.net)
        // Assign nil as well: disconnected drivers must clear their last reading.
        gpuName = frame.gpuName
        gpuUsage = frame.gpuUsage
        gpuTemp = frame.gpuTemp
        gpuPowerWatts = frame.gpuPowerWatts
        gpuPowerLimitWatts = frame.gpuPowerLimitWatts
        gpuFrequencyMHz = frame.gpuFrequencyMHz
        vramUsedMB = frame.vramUsedMB
        vramTotalMB = frame.vramTotalMB
        if let mhz = frame.gpuFrequencyMHz {
            gpuFrequencyHistory.append(mhz)
            let cap = samplingRate.tempCapacity
            if gpuFrequencyHistory.count > cap { gpuFrequencyHistory.removeFirst(gpuFrequencyHistory.count - cap) }
        }
        if let g = frame.gpuUsage {
            gpuHistory.append(g)
            let cap = samplingRate.tempCapacity
            if gpuHistory.count > cap { gpuHistory.removeFirst(gpuHistory.count - cap) }
        }
        if let w = frame.gpuPowerWatts {
            gpuPowerHistory.append(w)
            let cap = samplingRate.tempCapacity
            if gpuPowerHistory.count > cap { gpuPowerHistory.removeFirst(gpuPowerHistory.count - cap) }
        }
        if let mb = frame.vramUsedMB {
            vramHistory.append(mb)
            let cap = samplingRate.tempCapacity
            if vramHistory.count > cap { vramHistory.removeFirst(vramHistory.count - cap) }
        }
        if let w = frame.powerWatts {
            powerWatts = w
            powerHistory.append(w)
            let cap = samplingRate.tempCapacity
            if powerHistory.count > cap { powerHistory.removeFirst(powerHistory.count - cap) }
        }
        if let total = systemPowerWatts {
            systemPowerHistory.append(total)
            let cap = samplingRate.tempCapacity
            if systemPowerHistory.count > cap { systemPowerHistory.removeFirst(systemPowerHistory.count - cap) }
        }
        cpuFreq.liveGHz = frame.cpuFreqGHz
        cpuMaxFreqGHz = frame.cpuMaxFreqGHz
        if let ghz = frame.cpuFreqGHz {
            freqHistory.append(ghz)
            let cap = samplingRate.tempCapacity
            if freqHistory.count > cap { freqHistory.removeFirst(freqHistory.count - cap) }
        }
        if frame.load.sampled {
            loadHistory.append(frame.load.total)
            let cap = samplingRate.tempCapacity
            if loadHistory.count > cap { loadHistory.removeFirst(loadHistory.count - cap) }
        }

        if let b = frame.battery { battery = b }
        if let d = frame.disk { disk = d }
        if let d = frame.tiles { tiles = d }
        if let list = frame.processes { processes = list }

        sampleCount += 1

        // 背光档位：HID 通道读 Prefs、SMC 通道读一个键，都很便宜，放主线程即可
        if !kbdBusy, kbdMaxLevel > 0, sampleCount % 3 == 1 {
            let lv = Control.currentLevel()
            if lv != kbdLevel { kbdLevel = lv; kbdAssumed = false }
        }
        lastUpdate = frame.at

        let sample = MetricSample(
            time: frame.at,
            temp: cpuTemp,
            load: frame.load.sampled ? frame.load.total : (history.last?.load ?? 0),
            mem: frame.load.memoryUsedRatio,
            appCPU: nil,
            appMemMB: nil,
            freqGHz: frame.cpuFreqGHz,
            power: frame.powerWatts
        )
        appendHistory(sample)
        appendRecording(sample)

        // 通道不可用时每 5 个采样点复查一次（模式带 60 秒缓存，不会每次都枚举设备）
        if kbdMaxLevel == 0, sampleCount % 5 == 0 {
            let mode = Control.mode
            let permission = Control.permissionState
            if permission != kbdPermission { kbdPermission = permission }
            if mode.maxLevel > 0 {
                kbdMode = mode
                kbdMaxLevel = mode.maxLevel
                kbdAvailable = true
                kbdBlockedByPermission = false
                kbdLevel = Control.currentLevel()
            } else {
                kbdBlockedByPermission = (permission == .denied || permission == .needsRestart)
            }
        }
    }

    /// 重新检测背光通道与输入监控权限（授权/重启后可手动触发）
    func recheckBacklightPermission() {
        Control.invalidateMode()
        DispatchQueue.global(qos: .userInitiated).async {
            let mode = Control.mode
            let permission = Control.permissionState
            DispatchQueue.main.async {
                self.kbdMode = mode
                self.kbdPermission = permission
                self.kbdMaxLevel = mode.maxLevel
                self.kbdAvailable = mode.maxLevel > 0
                self.kbdBlockedByPermission = (permission == .denied || permission == .needsRestart)
                self.kbdLevel = Control.currentLevel()
                self.capabilities = Capabilities.all(gpus: self.hardware.gpus,
                                                     nvidia: self.nvidiaUpdate)
            }
        }
    }

    // MARK: - NVIDIA 驱动更新

    func checkNvidiaUpdate() {
        guard !nvidiaUpdate.isChecking else { return }
        let installed = NvidiaUpdate.installedVersion()
        guard let installed else {
            nvidiaUpdate = .notInstalled
            return
        }
        nvidiaUpdate = .checking
        NvidiaUpdate.fetchLatest(completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release):
                self.nvidiaRelease = release
                self.nvidiaUpdate = NvidiaUpdate.isNewer(release.tag, than: installed)
                    ? .available(installed: installed, latest: release.tag)
                    : .upToDate(installed: installed, latest: release.tag)
            case .failure(let error):
                self.nvidiaUpdate = .failed(installed: installed,
                                            message: error.localizedDescription)
            }
            // 能力矩阵里有一行要跟着更新
            self.capabilities = Capabilities.all(gpus: self.hardware.gpus,
                                                 nvidia: self.nvidiaUpdate)
        }, onEnrich: { [weak self] release in
            // 后台补到的发布说明，只更新展示，不改变版本状态
            self?.nvidiaRelease = release
        })
    }

    // MARK: - 按页面启用采样（不看监控页就不枚举进程）

    func setTilesActive(_ active: Bool) {
        sampleQueue.async { self.config.wantTiles = active }
    }

    func setProcessSamplingActive(_ active: Bool) {
        let pid = recording?.appPID
        sampleQueue.async {
            self.config.pageProcesses = active
            self.config.recordingPID = pid
        }
    }

    /// 读取全部 SMC 键（诊断页用）
    func reloadAllReadings(completion: (() -> Void)? = nil) {
        let store = self
        DispatchQueue.global(qos: .userInitiated).async {
            var list: [SMCReading] = []
            for name in store.keyNames {
                if let r = SMC.read(name) { list.append(r) }
            }
            let sorted = list.sorted { $0.key < $1.key }
            DispatchQueue.main.async {
                store.readings = sorted
                completion?()
            }
        }
    }

    // MARK: - 历史与录制

    private func appendHistory(_ sample: MetricSample) {
        var s = sample
        if let pid = recording?.appPID,
           let p = ProcessSampler.findByPID(processes, pid: pid) {
            s = MetricSample(time: sample.time, temp: sample.temp, load: sample.load,
                             mem: sample.mem, appCPU: p.cpu, appMemMB: p.memoryMB,
                             freqGHz: sample.freqGHz, power: sample.power)
        }
        history.append(s)
        let cap = samplingRate.historyCapacity
        if history.count > cap { history.removeFirst(history.count - cap) }
    }

    private func appendRecording(_ sample: MetricSample) {
        guard var rec = recording else { return }
        var s = sample
        if let pid = rec.appPID, let p = ProcessSampler.findByPID(processes, pid: pid) {
            s = MetricSample(time: sample.time, temp: sample.temp, load: sample.load,
                             mem: sample.mem, appCPU: p.cpu, appMemMB: p.memoryMB,
                             freqGHz: sample.freqGHz, power: sample.power)
        }
        rec.samples.append(s)
        recording = rec
        recordingTick &+= 1
    }

    func startRecording(label: String, appName: String?, appPID: Int32?) {
        recording = ActiveRecording(label: label.isEmpty ? "未命名录制" : label,
                                    appName: appName,
                                    appPID: appPID,
                                    start: Date())
        recordingTick = 0
        sampleQueue.async { self.config.recordingPID = appPID }
        objectWillChange.send()
    }

    @discardableResult
    func stopRecording() -> RecordingSummary? {
        guard let rec = recording else { return nil }
        recording = nil
        sampleQueue.async { self.config.recordingPID = nil }
        objectWillChange.send()
        let summary = RecordingStore.save(label: rec.label, appName: rec.appName,
                                          appPID: rec.appPID, start: rec.start,
                                          end: Date(), samples: rec.samples)
        recordings = RecordingStore.loadIndex()
        return summary
    }

    func deleteRecording(_ summary: RecordingSummary) {
        RecordingStore.delete(summary)
        recordings = RecordingStore.loadIndex()
    }

    /// 历史窗口（秒）
    func samples(window: Int) -> [MetricSample] {
        let cutoff = Date().addingTimeInterval(-Double(window))
        return history.filter { $0.time >= cutoff }
    }

    // MARK: - 键盘背光

    func setKeyboardBacklight(_ level: Int) {
        guard kbdMaxLevel > 0 else {
            kbdError = "当前机型不可控（见「诊断」页）"
            return
        }
        let clamped = max(0, min(kbdMaxLevel, level))
        kbdLevel = clamped
        kbdAssumed = true
        pendingKbd = clamped
        kbdError = nil

        kbdDebounce?.invalidate()
        kbdDebounce = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.commitKeyboardBacklight()
        }
        RunLoop.main.add(kbdDebounce!, forMode: .common)
    }

    private func commitKeyboardBacklight() {
        guard let level = pendingKbd else { return }
        pendingKbd = nil
        kbdBusy = true
        let store = self
        DispatchQueue.global(qos: .userInitiated).async {
            let err = Control.setBacklight(level)
            DispatchQueue.main.async {
                store.kbdBusy = false
                if let err {
                    store.kbdError = err
                } else {
                    store.kbdError = nil
                }
                store.kbdAssumed = false
                store.kbdLevel = Control.currentLevel()
                store.kbdPermission = Control.permissionState
                store.maybeRequestHIDPermission()
            }
        }
    }
    // MARK: - 派生值

    var tempText: String {
        guard let t = cpuTemp else { return "—" }
        return String(format: "%.0f", t)
    }

    var tempStatusText: String {
        guard let t = cpuTemp else { return "无数据" }
        switch t {
        case ..<55: return "凉爽"
        case ..<70: return "正常"
        case ..<85: return "偏高"
        case ..<95: return "高温"
        default: return "过热"
        }
    }

    /// 菜单栏标题：按「菜单栏」页里勾选的项目拼一段紧凑文本
    var menuBarTitle: String {
        let picked = MenuBarPrefs.enabled.compactMap { shortText($0) }
        return picked.isEmpty ? "天选控制中心" : picked.joined(separator: " ")
    }

    /// 菜单栏状态项用的结构化条目（图标 + 短标签 + 数值），供 App.swift 渲染图标版标签
    var menuBarItems: [MenuBarItem] {
        MenuBarPrefs.enabled.compactMap { metric in
            shortText(metric).map { MenuBarItem(metric: metric, value: $0) }
        }
    }

    /// 菜单栏窗口里每一行的完整显示（带项目名）
    func menuValue(_ metric: MenuMetric) -> MenuMetricValue {
        switch metric {
        case .cpuTemp:
            if let t = cpuTemp {
                return MenuMetricValue(text: String(format: "%.0f °C", t), available: true)
            }
            return MenuMetricValue(text: "—", available: false,
                                   reason: "未读到 CPU 温度；Intel 需要可用的 Intel Power Gadget / EnergyDriver，或 SMCProcessor 温度传感器；AMD 需要 SMCAMDProcessor")

        case .cpuLoad:
            guard load.sampled else {
                return MenuMetricValue(text: "—", available: false, reason: "采样中…")
            }
            return MenuMetricValue(text: String(format: "%.0f%%", load.total * 100), available: true)

        case .cpuFreq:
            if let ghz = cpuFreq.liveGHz {
                return MenuMetricValue(text: String(format: "%.2f GHz", ghz), available: true)
            }
            let nominal = cpuFreq.nominalHz > 0
                ? String(format: "sysctl 只给了一个标称值 %.2f GHz", Double(cpuFreq.nominalHz) / 1e9)
                : "sysctl 里连标称频率都没有"
            return MenuMetricValue(text: "不可用", available: false,
                                   reason: "实时频率需要 Intel Power Gadget / EnergyDriver 或 AMD 的 AMDRyzenCPUPowerManagement；\(nominal)")

        case .memUsage:
            guard load.memTotal > 0 else {
                return MenuMetricValue(text: "—", available: false, reason: "读不到内存统计")
            }
            return MenuMetricValue(text: String(format: "%.0f%%", load.memoryUsedRatio * 100), available: true)

        case .netSpeed:
            guard netSpeed.sampled else {
                return MenuMetricValue(text: "—", available: false, reason: "采样中…")
            }
            switch MenuBarPrefs.netMode {
            case .down: return MenuMetricValue(text: "↓ \(netSpeed.down.asRate)", available: true)
            case .up:   return MenuMetricValue(text: "↑ \(netSpeed.up.asRate)", available: true)
            case .both: return MenuMetricValue(text: "↓ \(netSpeed.down.asRate)  ↑ \(netSpeed.up.asRate)",
                                               available: true)
            }


        case .gpuLoad:
            guard let g = gpuUsage else {
                return MenuMetricValue(text: "不可用", available: false,
                                       reason: "当前 GPU 驱动未返回有效的核心利用率。")
            }
            return MenuMetricValue(text: String(format: "%.0f%%", g), available: true)

        case .gpuTemp:
            guard let t = gpuTemp else {
                return MenuMetricValue(text: "不可用", available: false,
                                       reason: "当前 GPU 驱动未返回有效的温度读数。")
            }
            return MenuMetricValue(text: String(format: "%.0f °C", t), available: true)

        case .gpuPower:
            guard let w = gpuPowerWatts else {
                return MenuMetricValue(text: "不可用", available: false,
                                       reason: "当前 GPU 驱动未提供功耗读数。")
            }
            return MenuMetricValue(text: String(format: "%.1f W", w), available: true)

        case .gpuFreq:
            guard let mhz = gpuFrequencyMHz else {
                return MenuMetricValue(text: "不可用", available: false,
                                       reason: "当前 GPU 驱动未提供核心频率读数。")
            }
            return MenuMetricValue(text: String(format: "%.0f MHz", mhz), available: true)

        case .gpuVRAM:
            guard let used = vramUsedMB else {
                return MenuMetricValue(text: "不可用", available: false,
                                       reason: "当前 GPU 驱动未提供有效的显存占用读数。")
            }
            if let total = vramTotalMB, total > 0 {
                return MenuMetricValue(text: String(format: "%.1f / %.1f GiB", used / 1024, total / 1024), available: true)
            }
            return MenuMetricValue(text: String(format: "%.1f GiB", used / 1024), available: true)

        case .power:
            guard let w = powerWatts else {
                return MenuMetricValue(text: "不可用", available: false,
                                   reason: "CPU 整包功耗需要 Intel Power Gadget / EnergyDriver 或 AMD 的 AMDRyzenCPUPowerManagement")
            }
            return MenuMetricValue(text: String(format: "%.1f W", w), available: true)
        }
    }

    /// 这一项在本机能不能用 —— 与「此刻有没有读到值」是两回事，
    /// 设置页用这个决定开关能不能点，避免采样间隙里开关来回闪
    func isAvailable(_ metric: MenuMetric) -> Bool {
        switch metric {
        case .cpuTemp:  return cpuTemp != nil
        case .cpuLoad:  return true
        case .cpuFreq:  return cpuFreq.live
        case .memUsage: return load.memTotal > 0
        case .netSpeed: return true
        case .gpuLoad:  return gpuUsage != nil
        case .gpuTemp:  return gpuTemp != nil
        case .gpuPower: return gpuPowerWatts != nil
        case .gpuFreq:  return gpuFrequencyMHz != nil
        case .gpuVRAM:  return vramUsedMB != nil
        case .power:    return powerWatts != nil
        }
    }

    func unavailableReason(_ metric: MenuMetric) -> String? {
        isAvailable(metric) ? nil : menuValue(metric).reason
    }

    /// 菜单栏标题用的紧凑写法（不带项目名，长度要控制）
    func shortText(_ metric: MenuMetric) -> String? {
        switch metric {
        case .cpuTemp:
            guard let t = cpuTemp else { return nil }
            return String(format: "%.0f°", t)
        case .cpuLoad:
            guard load.sampled else { return nil }
            return String(format: "%.0f%%", load.total * 100)
        case .memUsage:
            guard load.memTotal > 0 else { return nil }
            return String(format: "%.0f%%", load.memoryUsedRatio * 100)
        case .netSpeed:
            guard netSpeed.sampled else { return nil }
            switch MenuBarPrefs.netMode {
            case .down: return "↓\(netSpeed.down.asRate)"
            case .up:   return "↑\(netSpeed.up.asRate)"
            // 「上下行」以前只显示下行，跟设置名不符，补上上行
            case .both: return "↓\(netSpeed.down.asRate) ↑\(netSpeed.up.asRate)"
            }
        case .cpuFreq:
            guard let ghz = cpuFreq.liveGHz else { return nil }
            return String(format: "%.2fG", ghz)
        case .gpuLoad:
            guard let g = gpuUsage else { return nil }
            return String(format: "%.0f%%", g)
        case .gpuTemp:
            guard let t = gpuTemp else { return nil }
            return String(format: "%.0f°", t)
        case .gpuPower:
            guard let w = gpuPowerWatts else { return nil }
            return String(format: "%.0fW", w)
        case .gpuFreq:
            guard let mhz = gpuFrequencyMHz else { return nil }
            return String(format: "%.0fMHz", mhz)
        case .gpuVRAM:
            guard let used = vramUsedMB else { return nil }
            return String(format: "%.1fG", used / 1024)
        case .power:
            guard let w = powerWatts else { return nil }
            return String(format: "%.0fW", w)
        }
    }

    var availableCount: Int {
        capabilities.filter { $0.status != .unavailable }.count
    }
}
