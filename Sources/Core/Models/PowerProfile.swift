// PowerProfile.swift

import Foundation
import Combine

// MARK: - 档位定义

/// 四档：三档预设 + 自定义（上限 50W）
enum PowerProfile: String, CaseIterable, Identifiable {
    case quiet
    case balanced
    case performance
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quiet:       return "静音"
        case .balanced:    return "平衡"
        case .performance: return "性能"
        case .custom:      return "自定义"
        }
    }

    /// 预设档位的瓦数；自定义档返回 nil（由用户给值）
    var watts: Int? {
        switch self {
        case .quiet:       return 25
        case .balanced:    return 30
        case .performance: return 35
        case .custom:      return nil
        }
    }

    var hint: String {
        switch self {
        case .quiet:       return "最凉最安静，多核性能下降明显"
        case .balanced:    return "日常主力，发热与性能的折中"
        case .performance: return "给足功耗，适合编译、渲染、导出"
        case .custom:      return "在 \(PowerLimitSpec.minW)–\(PowerLimitSpec.maxW)W 之间自选"
        }
    }
}

/// 与 kext 约定的常量（改这里前先确认 kext 版本是 v20-stapm 及以上）
enum PowerLimitSpec {
    static let minW = 15
    static let maxW = 50
    /// SMU 消息号：0x15 / 0x16 实测精确生效；0x14 回 OK 但不执行，别用
    static let smuCmd: UInt8 = 0x15
    static let keyCmd = "AFsC"
    static let keyWatts = "AFsw"
    static let prefsProfile = "power.profile"
    static let prefsCustom = "power.customWatts"
    static let prefsUnlocked = "power.customUnlocked"
    /// 实测满载功耗（W），0 = 没测过
    static let prefsMeasured = "power.measuredCeiling"
    /// 实测时间（epoch 秒），0 = 没测过
    static let prefsMeasuredAt = "power.measuredCeilingAt"
}

/// 功耗墙走哪条通道
enum PowerBackend {
    /// SMCAsusFan.kext 暴露的 AFsC / AFsw（AMD 与部分 Intel 机型）
    case smc
    /// AsusECTool.kext 的 MSR 通道（Intel：RAPL 0x610）—— 本机走这条
    case rapl
    /// 都没有
    case none

    var label: String {
        switch self {
        case .smc:  return "SMU · AFsC / AFsw"
        case .rapl: return "Intel RAPL · MSR 0x610"
        case .none: return "无可用通道"
        }
    }

    /// 是否能在进程内直接下发（RAPL 走 kext，不需要管理员授权）
    var needsAdmin: Bool { self == .smc }
}

/// 通道探测（不碰 UI 状态，GUI 与 CLI、能力矩阵共用）
enum PowerWallProbe {
    /// SMC 键优先（原设计主线），其次 RAPL（Intel 机型）
    static var backend: PowerBackend {
        if SMC.exists(PowerLimitSpec.keyCmd) && SMC.exists(PowerLimitSpec.keyWatts) {
            return .smc
        }
        if RAPLBridge.shared.hasChannel { return .rapl }
        return .none
    }
}

