// ByteCountFormatter.swift

import Foundation

// MARK: - 字节格式化（磁盘容量）

extension ByteCountFormatter {
    /// 统一用「十进制 + 省略 decimals」风格展示磁盘容量（如 512 GB、1.2 TB），
    /// 避免系统默认在 B/KB 档跳来跳去，也更贴近厂商标称。
    static let vela: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useTB, .useMB]
        f.countStyle = .decimal
        f.includesUnit = true
        f.zeroPadsFractionDigits = false
        return f
    }()
}

