// EditableCurve.swift

import Foundation
import Combine

// MARK: - 数据模型

/// 编辑用的可变曲线（FanCurve 是只读值类型，UI 需要逐点拖动修改）。
struct EditableCurve: Equatable {
    var temp: [Int]
    var duty: [Int]

    /// 兜底初值：温和递增，8 点单调不减
    static let defaultCurve = EditableCurve(
        temp: [40, 48, 56, 64, 72, 80, 88, 96],
        duty: [28, 32, 40, 50, 62, 74, 86, 96]
    )

    init(temp: [Int], duty: [Int]) {
        self.temp = temp
        self.duty = duty
    }

    init(_ c: FanCurve) {
        self.temp = c.temp
        self.duty = c.duty
    }

    var points: Int { min(temp.count, duty.count) }

    func toFanCurve() -> FanCurve { FanCurve(temp: temp, duty: duty) }

    /// 单调 + 范围校验；通过返回 nil，否则返回可直接显示的中文原因。
    func validationError(points: Int,
                         tempRange: ClosedRange<Int>,
                         dutyRange: ClosedRange<Int>) -> String? {
        guard temp.count == points, duty.count == points else {
            return "需要 \(points) 个点（当前温度 \(temp.count) / 占空 \(duty.count)）"
        }
        for i in 1..<temp.count where temp[i] < temp[i - 1] {
            return "温度必须单调不减：第 \(i + 1) 点 \(temp[i])°C < 第 \(i) 点 \(temp[i - 1])°C"
        }
        for i in 1..<duty.count where duty[i] < duty[i - 1] {
            return "占空比必须单调不减：第 \(i + 1) 点 \(duty[i])% < 第 \(i) 点 \(duty[i - 1])%"
        }
        if let t0 = temp.first, t0 < tempRange.lowerBound {
            return "最低温度 \(t0)°C 低于机型允许的 \(tempRange.lowerBound)°C"
        }
        if let t1 = temp.last, t1 > tempRange.upperBound {
            return "最高温度 \(t1)°C 高于机型允许的 \(tempRange.upperBound)°C"
        }
        if let dMin = duty.min(), dMin < dutyRange.lowerBound {
            return "占空比 \(dMin)% 低于下限 \(dutyRange.lowerBound)%"
        }
        if let dMax = duty.max(), dMax > dutyRange.upperBound {
            return "占空比 \(dMax)% 超过上限 \(dutyRange.upperBound)%"
        }
        return nil
    }
}

/// 提权后 CLI 读取的曲线文件格式（/tmp/vela_custom_curve.json）。
struct CustomCurveFile: Codable {
    var cpu: FanCurve
    var gpu: FanCurve
}

