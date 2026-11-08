import Foundation
import CoreFoundation

/// A complete sample for one GPU. Missing fields stay nil so an old reading cannot
/// survive a driver disconnect or be confused with a genuine zero.
struct GPUStats {
    var name = "GPU"
    var vendorID: UInt32?
    var registryID: UInt64 = 0
    var usage: Double?
    var temperature: Double?
    var powerWatts: Double?
    var limitWatts: Double?
    var frequencyMHz: Double?
    var vramUsedMB: Double?
    var vramTotalMB: Double?

    var hasReadings: Bool {
        [usage, temperature, powerWatts, frequencyMHz, vramUsedMB, vramTotalMB].contains { $0 != nil }
    }

    /// The global NVIDIA sysctls can only be joined to a selected NVIDIA device.
    func mergingNvidia(_ fallback: GPUStats) -> GPUStats {
        guard vendorID == 0x10de else { return self }
        var result = self
        result.powerWatts = powerWatts ?? fallback.powerWatts
        result.limitWatts = limitWatts ?? fallback.limitWatts
        result.frequencyMHz = frequencyMHz ?? fallback.frequencyMHz
        result.vramUsedMB = vramUsedMB ?? fallback.vramUsedMB
        result.vramTotalMB = vramTotalMB ?? fallback.vramTotalMB
        return TelemetryParsing.validatedMemory(result)
    }
}

enum TelemetryParsing {
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let v = n.doubleValue
        return v.isFinite ? v : nil
    }

    static func bounded(_ value: Double?, _ range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    static func text(_ value: Any?) -> String? {
        let string: String?
        if let data = value as? Data { string = String(data: data, encoding: .utf8) }
        else { string = value as? String }
        guard let value = string?.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)), !value.isEmpty else { return nil }
        return value
    }

    static func vendorID(_ value: Any?) -> UInt32? {
        if let data = value as? Data, data.count >= 2 {
            return data.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
        }
        guard let n = number(value), n >= 0, n <= Double(UInt32.max), n.rounded() == n else { return nil }
        return UInt32(n)
    }

    static func gpu(properties: [String: Any], pci: [String: Any], registryID: UInt64 = 0) -> GPUStats {
        let stats = properties["PerformanceStatistics"] as? [String: Any] ?? [:]
        let accum = properties["PerformanceStatisticsAccum"] as? [String: Any] ?? [:]
        func first(_ keys: [String], range: ClosedRange<Double>, scale: Double = 1) -> Double? {
            for key in keys {
                if let n = number(stats[key]), let v = bounded(n * scale, range) { return v }
            }
            return nil
        }
        var result = GPUStats()
        result.name = text(pci["model"]) ?? text(properties["model"]) ?? text(properties["IOName"]) ?? "GPU"
        result.vendorID = vendorID(pci["vendor-id"])
        result.registryID = registryID
        // Keys explicitly marked % are percentages, including 0% and 1%.
        result.usage = first(["Device Utilization %", "GPU Core Utilization %", "GPU Utilization %"], range: 0...100)
            ?? first(["Device Utilization Ratio", "GPU Core Utilization Ratio"], range: 0...100, scale: 100)
        result.temperature = first(["Temperature(C)", "GPU Temperature(C)"], range: 0...150)
        result.powerWatts = first(["GPU Power(W)", "GPU Power (W)", "Power Consumption(W)"], range: 0...2000)
            ?? first(["GPU Power(mW)", "GPU Power (mW)"], range: 0...2000, scale: 0.001)
        result.limitWatts = first(["GPU Power Limit(W)", "GPU Power Limit (W)"], range: 0.001...2000)
        // Display pixel clocks and memory clocks are deliberately excluded.
        result.frequencyMHz = first(["GPU Core Clock(MHz)", "GPU Core Clock (MHz)", "Core Clock(MHz)", "GPU Core Frequency(MHz)"], range: 0...10000)
            ?? first(["GPU Core Clock(Hz)", "GPU Core Frequency(Hz)"], range: 0...10000, scale: 0.000001)
        let mib = 1_048_576.0
        result.vramUsedMB = bounded(number(accum["inUseVidMemoryBytes"]).map { $0 / mib }, 0...1_048_576)
        result.vramTotalMB = bounded(number(pci["VRAM,totalsize"]).map { $0 / mib }, 1...1_048_576)
            ?? bounded(number(pci["VRAM,totalMB"]), 1...1_048_576)
        return validatedMemory(result)
    }

    static func validatedMemory(_ sample: GPUStats) -> GPUStats {
        var result = sample
        if let used = sample.vramUsedMB, let total = sample.vramTotalMB, used > total { result.vramUsedMB = nil }
        return result
    }

    /// Stable choice: prefer the discrete NVIDIA GPU, then AMD, then Intel.
    /// All fields come from that candidate, even if another GPU has more metrics.
    static func preferredGPU(_ samples: [GPUStats]) -> GPUStats? {
        func rank(_ sample: GPUStats) -> Int {
            switch sample.vendorID {
            case 0x10de: return 0
            case 0x1002: return 1
            case 0x8086: return 2
            default: return 3
            }
        }
        return samples.sorted {
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            if $0.hasReadings != $1.hasReadings { return $0.hasReadings }
            return $0.registryID < $1.registryID
        }.first
    }
}

struct FanSnapshot {
    var cpuRPM: Double?
    var gpuRPM: Double?
    var centerRPM: Double?
    var reportedCount = 0
    var sources: [String] = []

    static func validRPM(_ value: Double?) -> Double? { TelemetryParsing.bounded(value, 0...8000) }
    /// A zero from an undeclared SMC slot may be a placeholder.
    static func smcRPM(_ value: Double?, index: Int, declaredCount: Int) -> Double? {
        guard let rpm = validRPM(value), rpm > 0 || declaredCount > index else { return nil }
        return rpm
    }

    /// Resolve channels independently and only call a fallback when needed.
    static func resolve(declaredWMI: Int, declaredSMC: Int,
                        wmi: (Int) -> Double?, smc: (Int) -> Double?,
                        ec: ((Int) -> Double?)? = nil) -> FanSnapshot {
        var result = FanSnapshot(reportedCount: max(declaredWMI, declaredSMC))
        func record(_ value: Double, source: String) -> Double {
            if !result.sources.contains(source) { result.sources.append(source) }
            return value
        }
        func channel(_ index: Int) -> Double? {
            if let rpm = validRPM(wmi(index)) { return record(rpm, source: "华硕 WMI") }
            if let rpm = smcRPM(smc(index), index: index, declaredCount: declaredSMC) {
                return record(rpm, source: "AppleSMC")
            }
            if let rpm = validRPM(ec?(index)) { return record(rpm, source: "AsusECTool EC tach") }
            return nil
        }
        result.cpuRPM = channel(0)
        result.gpuRPM = channel(1)
        if let center = validRPM(ec?(2)), center > 0 || result.reportedCount >= 3 {
            result.centerRPM = record(center, source: "AsusECTool EC tach")
        }
        return result
    }
    var readableCount: Int { [cpuRPM, gpuRPM, centerRPM].compactMap { $0 }.count }
    var count: Int { max(reportedCount, readableCount) }
    var isAvailable: Bool { readableCount > 0 }
    var backendLabel: String { sources.isEmpty ? "不可用" : sources.joined(separator: " / ") }
}
