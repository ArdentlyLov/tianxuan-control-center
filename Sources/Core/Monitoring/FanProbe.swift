import Foundation

/// Collect each fan channel once; a valid zero means the fan is stopped.
enum FanProbe {
    // These EC tach offsets are verified only on G815LM, never use a user override.
    private static let legacyECAllowed = ModelDetector.detect().code.uppercased() == "G815LM"

    static func sample() -> FanSnapshot {
        let wmi = ASUSWMIBridge.shared
        let declaredWMI = wmi.fanCount
        let rawSMCCount = TelemetryParsing.bounded(SMC.read("FNum")?.number, 0...8) ?? 0
        let smcCount = Int(rawSMCCount)
        let ec: ((Int) -> Double?)? = legacyECAllowed ? { index in
            ECFanBridge.shared.rpm(index == 0 ? .cpu : index == 1 ? .gpu : .center).map(Double.init)
        } : nil
        return FanSnapshot.resolve(declaredWMI: declaredWMI, declaredSMC: smcCount,
                                   wmi: { wmi.rpm(cpu: $0 == 0).map(Double.init) },
                                   smc: { SMC.read("F\($0)Ac")?.number }, ec: ec)
    }

    static var count: Int { sample().count }
    static var rpm: Double? { sample().cpuRPM }
    static var gpuRPM: Double? { sample().gpuRPM }
    static var centerRPM: Double? { sample().centerRPM }
    static var isAvailable: Bool { sample().isAvailable }
    static var backendLabel: String { sample().backendLabel }
    static var unavailableReason: String {
        ASUSWMIBridge.shared.isAvailable
            ? "风扇接口已连接，但固件尚未返回有效转速；SMC / EC 也没有可用反馈。"
            : "未连接到华硕 WMI 风扇反馈接口，SMC 也未提供有效转速；EC 读取仅支持已验证机型。"
    }
}
