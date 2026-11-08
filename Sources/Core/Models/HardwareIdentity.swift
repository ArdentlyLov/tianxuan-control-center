import Foundation

struct HardwareFingerprint {
    var vendor = ""
    /// 完整 CPU 品牌串，如 "AMD Ryzen 9 6900HX with Radeon Graphics"
    var cpu = ""
    /// 从品牌串里抠出的型号代号，如 "6900HX"。
    /// 用代号而不是整串比较，是因为 **HS / H / HX 后缀本身就是机型分界线**：
    /// 幻15 用 6900HS，魔霸6 用 6900HX/6800H，魔霸7 Plus 用 7945HX。
    var cpuCode = ""
    var gpus: [String] = []
    /// 出厂电池容量（Wh），0 = 读不到
    var batteryWh: Double = 0
    /// 电池上报的部件号（弱证据，只展示不判定）
    var batteryName: String?
    /// 主屏描述，如 "3360×1890 @165Hz"
    var screen: String?
    /// 主屏长边像素（区分 1080p / 1440p / 4K 档）
    var screenPixels = 0
    var ramGB: Double = 0
    /// 被 OpenCore 覆盖后的 SMBIOS 型号，只用来提示「这个值不可信」
    var smbiosModel = ""
}


enum HardwareIdentity {
    static func cpuCode(from brand: String) -> String {
        let pattern = "\\b(\\d{3,5}[A-Za-z]{1,3})\\b"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: brand, range: NSRange(brand.startIndex..., in: brand)),
              let r = Range(m.range(at: 1), in: brand) else { return "" }
        return String(brand[r]).uppercased()
    }
}
