import Foundation

/// Exercise real driver payloads and failure transitions without accessing hardware.
@main
struct TelemetryTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fatalError("FAILED: \(label)") }
            checks += 1
        }
        func close(_ value: Double?, _ expected: Double) -> Bool {
            value.map { abs($0 - expected) < 0.00001 } ?? false
        }
        let pci: [String: Any] = [
            "model": Data("NVIDIA GeForce RTX 3060 Laptop GPU\0".utf8),
            "vendor-id": Data([0xde, 0x10, 0, 0]),
            "VRAM,totalsize": UInt64(6_442_450_944), "VRAM,totalMB": 6144
        ]
        func gpu(_ stats: [String: Any], accum: [String: Any] = [:],
                 device: [String: Any] = pci) -> GPUStats {
            TelemetryParsing.gpu(properties: ["PerformanceStatistics": stats,
                                              "PerformanceStatisticsAccum": accum], pci: device)
        }

        let live = gpu(["Device Utilization %": 0, "GPU Core Utilization %": 0,
                        "GPU Memory Utilization %": 1, "Temperature(C)": 53],
                       accum: ["inUseVidMemoryBytes": UInt64(460_726_272),
                               "inUseSysMemoryBytes": 123456, "gartSizeBytes": UInt64(5_726_625_792)])
        check(live.name == "NVIDIA GeForce RTX 3060 Laptop GPU" && live.vendorID == 0x10de, "PCI identity")
        check(close(live.vramUsedMB, 439.3828125) && live.vramTotalMB == 6144, "native VRAM: used bytes and physical capacity")
        check(live.usage == 0 && live.temperature == 53, "native idle GPU and temperature")
        check(live.powerWatts == nil && live.frequencyMHz == nil, "missing power and clocks stay unavailable")
        check(gpu(["Device Utilization %": 1]).usage == 1, "1 percent is not 100 percent")
        check(gpu(["Device Utilization Ratio": 0.01]).usage == 1, "explicit fractional ratio")
        check(gpu(["Device Utilization %": 0.01]).usage == 0.01, "fractional percent preserves units")
        check(gpu(["Device Utilization Ratio": 1.01]).usage == nil, "ratio above one rejected")
        check(gpu(["GPU Memory Utilization %": 89, "Video Engine Utilization %": 90]).usage == nil, "memory and video activity are not GPU core load")

        check(gpu(["GPU Power(W)": 82.5]).powerWatts == 82.5, "power watts")
        check(gpu(["GPU Power(mW)": 82500]).powerWatts == 82.5, "power milliwatts")
        check(gpu(["GPU Core Clock(MHz)": 1320]).frequencyMHz == 1320, "core MHz")
        check(gpu(["GPU Core Clock(Hz)": 1_320_000_000]).frequencyMHz == 1320, "core Hz")
        check(gpu(["Memory Clock(MHz)": 7000, "Pixel Clock(MHz)": 144, "Clock Frequency": 480]).frequencyMHz == nil, "unrelated clocks excluded")
        for bad: Any in [true, Double.nan, Double.infinity, -1, UInt64.max, 2_000_001] {
            let sample = gpu(["Device Utilization %": bad, "Temperature(C)": bad,
                              "GPU Power(W)": bad, "GPU Core Clock(MHz)": bad])
            check(sample.usage == nil && sample.temperature == nil && sample.powerWatts == nil && sample.frequencyMHz == nil,
                  "invalid telemetry rejected: \(bad)")
        }
        check(TelemetryParsing.number("100") == nil, "untyped text is not a sensor reading")
        check(gpu(["GPU Power(W)": true, "GPU Power(mW)": 35000]).powerWatts == 35, "invalid primary key does not block valid fallback")
        check(gpu([:], accum: ["inUseVidMemoryBytes": -1]).vramUsedMB == nil, "negative VRAM sentinel")
        check(gpu([:], accum: ["inUseVidMemoryBytes": UInt64.max]).vramUsedMB == nil, "unsigned VRAM sentinel")
        check(gpu([:], accum: ["inUseVidMemoryBytes": 0]).vramUsedMB == 0, "empty VRAM valid")
        check(gpu([:], accum: ["inUseVidMemoryBytes": UInt64(7) * 1_073_741_824]).vramUsedMB == nil, "used VRAM exceeds physical capacity")
        check(gpu([:], device: ["VRAM,totalMB": 6144]).vramTotalMB == 6144, "capacity MiB fallback")
        check(gpu([:], device: ["VRAM,totalMB": 0]).vramTotalMB == nil, "zero capacity unavailable")

        let intel = GPUStats(name: "Intel", vendorID: 0x8086, registryID: 1, usage: 99, frequencyMHz: 900)
        let amd = GPUStats(name: "AMD", vendorID: 0x1002, registryID: 2, usage: 80, powerWatts: 120)
        var nvidia = live
        nvidia.registryID = 3
        for list in [[intel, amd, nvidia], [nvidia, amd, intel], [amd, nvidia, intel]] {
            let preferred = TelemetryParsing.preferredGPU(list)
            check(preferred?.registryID == 3 && preferred?.usage == 0 && preferred?.frequencyMHz == nil,
                  "stable discrete GPU selection without mixing metrics")
        }
        check(TelemetryParsing.preferredGPU([intel, amd])?.name == "AMD", "AMD before integrated Intel")
        check(TelemetryParsing.preferredGPU([]) == nil, "no accelerator")
        let fallback = GPUStats(vendorID: 0x10de, powerWatts: 50, frequencyMHz: 1000, vramUsedMB: 900, vramTotalMB: 8192)
        let merged = live.mergingNvidia(fallback)
        check(merged.powerWatts == 50 && merged.vramUsedMB == live.vramUsedMB && merged.vramTotalMB == 6144, "same-device fallback preserves native data")
        check(amd.mergingNvidia(fallback).frequencyMHz == nil, "NVIDIA fallback never enters AMD sample")
        check(GPUStats(vendorID: 0x10de, vramTotalMB: 6144).mergingNvidia(GPUStats(vramUsedMB: 7000)).vramUsedMB == nil,
              "merged VRAM also validates physical capacity")

        var values: [String: Int64] = ["kern.nvgpupower": 85500, "kern.nvgpupwrlimit": 140000,
                                        "kern.nvgvramused": 500, "kern.nvgvramtotal": 6144]
        var sampledKeys = Set<String>()
        func sample() -> GPUStats {
            NvidiaRUSD.sample { key in sampledKeys.insert(key); return values[key] }
        }
        let online = sample()
        check(online.powerWatts == 85.5 && online.limitWatts == 140 && online.vramUsedMB == 500, "NVIDIA sysctl units")
        values = [:]
        check(!sample().hasReadings, "disconnect clears all NVIDIA values")
        values = ["kern.nvgpuinstpower": 42500, "kern.nvgvramused": 0, "kern.nvgvramtotal": 6144]
        let reconnected = sample()
        check(reconnected.powerWatts == 42.5 && reconnected.vramUsedMB == 0, "reconnect and instant power fallback")
        values = ["kern.nvgpupower": -1, "kern.nvgpuinstpower": 25000, "kern.nvgpupwrlimit": -1,
                  "kern.nvgvramused": -1, "kern.nvgvramtotal": 0]
        let sentinel = sample()
        check(sentinel.powerWatts == 25 && sentinel.limitWatts == nil && sentinel.vramUsedMB == nil && sentinel.vramTotalMB == nil,
              "NVIDIA sentinels rejected before fallback")
        check(sampledKeys == Set(["kern.nvgpupower", "kern.nvgpuinstpower", "kern.nvgpupwrlimit", "kern.nvgvramused", "kern.nvgvramtotal"]),
              "only known driver ABI names queried")

        var calls: [String] = []
        let independent = FanSnapshot.resolve(declaredWMI: 2, declaredSMC: 0,
            wmi: { calls.append("W\($0)"); return $0 == 0 ? nil : 3100 },
            smc: { calls.append("S\($0)"); return $0 == 0 ? 2800 : nil },
            ec: { calls.append("E\($0)"); return nil })
        check(independent.cpuRPM == 2800 && independent.gpuRPM == 3100, "CPU fallback cannot hide GPU WMI fan")
        check(calls == ["W0", "S0", "W1", "E2"], "lazy channel fallback avoids unnecessary hardware reads")
        check(independent.sources == ["AppleSMC", "华硕 WMI"] && independent.count == 2, "fan sources and declared channels")

        let gpuOnly = FanSnapshot.resolve(declaredWMI: 0, declaredSMC: 0,
            wmi: { _ in nil }, smc: { $0 == 1 ? 3000 : nil })
        check(gpuOnly.isAvailable && gpuOnly.cpuRPM == nil && gpuOnly.gpuRPM == 3000, "GPU-only fan works despite FNum zero")
        let stopped = FanSnapshot.resolve(declaredWMI: 0, declaredSMC: 2,
            wmi: { _ in nil }, smc: { _ in 0 })
        check(stopped.cpuRPM == 0 && stopped.gpuRPM == 0 && stopped.isAvailable, "declared stopped fans remain valid")
        check(stopped.sources == ["AppleSMC"], "duplicate fan sources collapsed")
        let phantom = FanSnapshot.resolve(declaredWMI: 0, declaredSMC: 0,
            wmi: { _ in nil }, smc: { _ in 0 })
        check(!phantom.isAvailable && phantom.count == 0, "undeclared placeholder zero unavailable")
        let invalidFans = FanSnapshot.resolve(declaredWMI: 2, declaredSMC: 2,
            wmi: { _ in 10000 }, smc: { _ in Double.nan }, ec: { _ in -1 })
        check(!invalidFans.isAvailable && invalidFans.count == 2, "declared channels are not readable channels")
        let center = FanSnapshot.resolve(declaredWMI: 0, declaredSMC: 0,
            wmi: { _ in nil }, smc: { _ in nil }, ec: { _ in 2200 })
        check(center.centerRPM == 2200 && center.count == 3 && center.sources == ["AsusECTool EC tach"], "legacy three-fan feedback")
        let centerZero = FanSnapshot.resolve(declaredWMI: 0, declaredSMC: 2,
            wmi: { _ in nil }, smc: { _ in 0 }, ec: { _ in 0 })
        check(centerZero.centerRPM == nil, "two-fan device has no phantom stopped center fan")
        print("PASS: \(checks) GPU telemetry and fan fallback checks")
    }
}
