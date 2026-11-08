import Foundation

/// Factory presets select the firmware policy. Rewriting their curves would
/// turn an automatic BIOS policy into a manually supplied fan curve.
enum FanPresetApplication {
    static func apply(name: String, isFirmwarePreset: Bool, usesWMI: Bool,
                      setMode: (Int) -> Bool, writeCurves: () throws -> Void) throws {
        let mode: Int
        switch name {
        case "silent": mode = 2
        case "balanced": mode = 0
        case "performance": mode = 1
        default: throw failure("未知风扇档位")
        }
        guard !isFirmwarePreset || usesWMI else {
            throw failure("本机固件控制连接已失效，请重新连接控制驱动")
        }
        if usesWMI, !setMode(mode) {
            throw failure("无法切换对应的本机性能模式")
        }
        if !isFirmwarePreset { try writeCurves() }
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "VelaX", code: 7, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
