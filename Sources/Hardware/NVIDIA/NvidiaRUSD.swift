import Foundation
import Darwin

/// Optional NVIDIA telemetry exported by SMCNvidiaGPU-PowerVRAM.
/// Power sysctls are milliwatts; VRAM sysctls are MiB. Re-probe on every sample
/// so a driver appearing or disappearing does not leave a permanent cache.
enum NvidiaRUSD {
    static var powerAvailable: Bool { sample().powerWatts != nil }
    static var vramAvailable: Bool { sample().vramUsedMB != nil }
    static var isAvailable: Bool { powerAvailable || vramAvailable }

    static func sample(reader: (String) -> Int64? = integer) -> GPUStats {
        func read(_ name: String, scale: Double = 1, range: ClosedRange<Double>) -> Double? {
            TelemetryParsing.bounded(reader(name).map { Double($0) * scale }, range)
        }
        var result = GPUStats(vendorID: 0x10de)
        result.powerWatts = read("kern.nvgpupower", scale: 0.001, range: 0...2000)
            ?? read("kern.nvgpuinstpower", scale: 0.001, range: 0...2000)
        result.limitWatts = read("kern.nvgpupwrlimit", scale: 0.001, range: 0.001...2000)
        result.vramUsedMB = read("kern.nvgvramused", range: 0...1_048_576)
        result.vramTotalMB = read("kern.nvgvramtotal", range: 1...1_048_576)
        return TelemetryParsing.validatedMemory(result)
    }

    /// 读一个整型 sysctl。这些键可能是 int32 也可能是 int64，所以先按返回的
    /// 实际长度解码，不写死类型 —— 驱动改一下宽度也不至于读出垃圾。
    static func integer(_ name: String) -> Int64? {
        var buf = [UInt8](repeating: 0, count: 8)
        var size = buf.count
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0, size > 0 else { return nil }
        switch size {
        case 8:
            var v: Int64 = 0
            withUnsafeMutableBytes(of: &v) { $0.copyBytes(from: buf) }
            return v
        case 4:
            var v: Int32 = 0
            withUnsafeMutableBytes(of: &v) { $0.copyBytes(from: buf.prefix(4)) }
            return Int64(v)
        case 2:
            var v: Int16 = 0
            withUnsafeMutableBytes(of: &v) { $0.copyBytes(from: buf.prefix(2)) }
            return Int64(v)
        case 1:
            return Int64(Int8(bitPattern: buf[0]))
        default:
            return nil
        }
    }
}
