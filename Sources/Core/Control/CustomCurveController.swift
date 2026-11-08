// CustomCurveController.swift

import Foundation
import Combine

// MARK: - 控制器（单一数据源 + 下发）

@MainActor
final class CustomCurveController: ObservableObject {
    static let shared = CustomCurveController()

    @Published private(set) var cpu: EditableCurve
    @Published private(set) var gpu: EditableCurve
    @Published private(set) var applying = false
    @Published private(set) var message: String?
    /// 是否已成功下发过（仅用于界面提示）
    @Published private(set) var lastApplied = false
    /// 功能解锁开关：默认关，需在「高级功能」页确认风险后解锁
    @Published private(set) var unlocked: Bool

    private let fan = FanControl.shared
    private var seeded = false

    private init() {
        unlocked = Prefs.bool("fan.customUnlocked")
        if let json = Prefs.string("fan.customCurve"),
           let data = json.data(using: .utf8),
           let file = try? JSONDecoder().decode(CustomCurveFile.self, from: data),
           file.cpu.temp.count == 8, file.gpu.temp.count == 8 {
            cpu = EditableCurve(file.cpu)
            gpu = EditableCurve(file.gpu)
            seeded = true
        } else {
            cpu = .defaultCurve
            gpu = .defaultCurve
        }
    }

    /// 首次进入页面时，若还没有自定义曲线，用该机型的「平衡」预设做初值
    func ensureSeededFromPresets() {
        guard !seeded else { return }
        if let p = fan.presets?.preset("balanced") {
            cpu = EditableCurve(p.cpu)
            gpu = EditableCurve(p.gpu)
            seeded = true
        }
    }

    func update(_ which: FanController.Fan, _ curve: EditableCurve) {
        if which == .cpu { cpu = curve } else { gpu = curve }
    }

    func seed(from preset: String) {
        guard let p = fan.presets?.preset(preset) else { return }
        cpu = EditableCurve(p.cpu)
        gpu = EditableCurve(p.gpu)
        seeded = true
    }

    // 机型 EC 配置决定点数与温度/占空范围
    var tempRange: ClosedRange<Int> {
        (fan.ecProfile?.tempMin ?? 20)...(fan.ecProfile?.tempMax ?? 110)
    }
    var dutyRange: ClosedRange<Int> {
        (fan.ecProfile?.dutyMin ?? 0)...(fan.ecProfile?.dutyMax ?? 100)
    }
    var pointCount: Int { fan.ecProfile?.curvePoints ?? 8 }

    func validationError() -> String? {
        let pts = pointCount, tr = tempRange, dr = dutyRange
        if let e = cpu.validationError(points: pts, tempRange: tr, dutyRange: dr) {
            return "CPU：" + e
        }
        if let e = gpu.validationError(points: pts, tempRange: tr, dutyRange: dr) {
            return "GPU：" + e
        }
        return nil
    }

    /// 机型不匹配 / 未识别且尚未确认风险 → 需要先确认
    var needsRiskConfirm: Bool {
        fan.status != .matched && !fan.acknowledgedMismatch
    }

    var riskMessage: String {
        fan.status == .mismatched
            ? ModelDisclaimer.short(selected: fan.selectedCode, detected: fan.detection.code)
            : ModelDisclaimer.shortUndetected(selected: fan.selectedCode)
    }

    func acknowledgeRisk() {
        fan.acknowledgeMismatch()
    }

    /// 高级功能页确认风险后解锁 / 关闭
    func unlock() {
        unlocked = true
        Prefs.set(true, for: "fan.customUnlocked")
    }

    func lock() {
        unlocked = false
        Prefs.set(false, for: "fan.customUnlocked")
    }

    /// 下发自定义曲线：写临时 JSON → 以 root 重跑自身 CLI `fan apply-custom`
    func apply() {
        guard !applying else { return }
        if let err = validationError() { message = err; return }
        if needsRiskConfirm { message = riskMessage; return }

        let file = CustomCurveFile(cpu: cpu.toFanCurve(), gpu: gpu.toFanCurve())
        guard let data = try? JSONEncoder().encode(file) else {
            message = "曲线编码失败"
            return
        }
        // 路径不能带空格：Admin 提权时参数是按空格拼接的
        let path = "/tmp/vela_custom_curve.json"
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            message = "写入曲线文件失败：\(error.localizedDescription)"
            return
        }

        applying = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Admin.runSelfAsAdmin(["fan", "apply-custom", path])
            DispatchQueue.main.async {
                self.applying = false
                if result.ok {
                    self.lastApplied = true
                    self.persist()
                    // 让「当前档位」切到 custom，预设不再显示「使用中」
                    FanControl.shared.noteCustomApplied()
                    self.message = "已下发自定义曲线，转速通常几秒内跟上"
                } else {
                    let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.message = text.isEmpty ? "自定义曲线下发失败（未拿到输出）" : text
                }
            }
        }
    }

    private func persist() {
        let file = CustomCurveFile(cpu: cpu.toFanCurve(), gpu: gpu.toFanCurve())
        if let data = try? JSONEncoder().encode(file),
           let s = String(data: data, encoding: .utf8) {
            Prefs.set(s, for: "fan.customCurve")
        }
    }
}

