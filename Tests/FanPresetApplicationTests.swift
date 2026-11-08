import Foundation

@main struct FanPresetApplicationTests {
    static func main() throws {
        for (name, mode) in [("silent", 2), ("balanced", 0), ("performance", 1)] {
            var writes: [String] = []
            try FanPresetApplication.apply(name: name, isFirmwarePreset: true, usesWMI: true,
                                           setMode: { writes.append("mode:\($0)"); return true },
                                           writeCurves: { writes.append("curves") })
            precondition(writes == ["mode:\(mode)"], "Factory policies must never submit manual fan curves")
        }
        var writes: [String] = []
        try FanPresetApplication.apply(name: "performance", isFirmwarePreset: false, usesWMI: true,
                                       setMode: { writes.append("mode:\($0)"); return true },
                                       writeCurves: { writes.append("curves") })
        precondition(writes == ["mode:1", "curves"], "File presets still submit curves after selecting the policy")
        writes = []
        try FanPresetApplication.apply(name: "balanced", isFirmwarePreset: false, usesWMI: false,
                                       setMode: { _ in fatalError("Legacy backend must not write WMI") },
                                       writeCurves: { writes.append("curves") })
        precondition(writes == ["curves"])
        for (factory, wmi) in [(true, true), (true, false), (false, true)] {
            writes = []
            do {
                try FanPresetApplication.apply(name: "performance", isFirmwarePreset: factory, usesWMI: wmi,
                                               setMode: { _ in false },
                                               writeCurves: { writes.append("curves") })
                fatalError("Unavailable / rejected policy must fail")
            } catch { precondition(writes.isEmpty, "Failure must not proceed to hardware curve writes") }
        }
        print("PASS factory policy only, file / legacy curves, rejected mode and disconnected firmware")
    }
}
