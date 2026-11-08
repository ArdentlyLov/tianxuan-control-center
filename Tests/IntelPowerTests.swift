import Foundation
import Darwin

enum SMC {
    struct Reading { var number: Double? }
    static var readings: [String: Double] = [:]
    static func exists(_ key: String) -> Bool { readings[key] != nil }
    static func read(_ key: String) -> Reading? { readings[key].map { Reading(number: $0) } }
}

@main struct IntelPowerTests {
    static func main() {
        let path = CommandLine.arguments[1]
        let library = dlopen(path, RTLD_NOW | RTLD_LOCAL)!
        defer { dlclose(library) }
        func symbol<T>(_ name: String, _: T.Type) -> T { unsafeBitCast(dlsym(library, name)!, to: T.self) }
        let reset = symbol("MockReset", (@convention(c) () -> Void).self)
        let mode = symbol("MockMode", (@convention(c) (Int32) -> Void).self)
        let live = symbol("MockLive", (@convention(c) () -> Int32).self)
        let released = symbol("MockReleased", (@convention(c) () -> Int32).self)
        let shutdowns = symbol("MockShutdowns", (@convention(c) () -> Int32).self)
        reset()
        var probe: IntelPowerProbe? = IntelPowerProbe(libraryPath: path)
        precondition(probe!.available && live() == 1)
        let good = probe!.sample()
        precondition(good.temperature == 57 && good.powerWatts == 18.5 && good.avgFreqGHz == 2.35)
        precondition(good.maxFreqGHz == 4.5)
        precondition(live() == 1 && released() == 1, "retain only the latest sample")
        for _ in 0..<100 { _ = probe!.sample() }
        precondition(live() == 1, "repeated sampling must not leak")
        mode(1)
        let invalid = probe!.sample()
        precondition(invalid.temperature == nil && invalid.powerWatts == nil && invalid.avgFreqGHz == nil)
        precondition(invalid.maxFreqGHz == nil)
        mode(5)
        let lowAverage = probe!.sample()
        precondition(lowAverage.avgFreqGHz == 0.4 && lowAverage.maxFreqGHz == 4.5,
                     "A low average must not hide an active high-frequency core")
        mode(6)
        let invalidPeak = probe!.sample()
        precondition(invalidPeak.avgFreqGHz == 2.35 && invalidPeak.maxFreqGHz == nil)
        mode(2)
        let before = released()
        let failed = probe!.sample()
        precondition(failed.temperature == nil && failed.powerWatts == nil && failed.avgFreqGHz == nil)
        precondition(failed.maxFreqGHz == nil)
        precondition(live() == 1 && released() == before, "failed read preserves previous sample")
        mode(3)
        let unsupported = probe!.sample()
        precondition(unsupported.temperature == nil && unsupported.powerWatts == nil && unsupported.avgFreqGHz == nil)
        precondition(unsupported.maxFreqGHz == nil)
        mode(0)
        precondition(probe!.sample().powerWatts == 18.5, "recover after failed reads")
        probe = nil
        precondition(live() == 0 && shutdowns() == 1, "release final sample and shutdown")
        reset(); mode(4)
        precondition(!IntelPowerProbe(libraryPath: path).available && live() == 0 && shutdowns() == 1)
        precondition(!IntelPowerProbe(libraryPath: "/nonexistent/IntelPowerGadget").available)
        precondition(!IntelPowerProbe(libraryPath: "/usr/lib/libSystem.B.dylib").available)
        SMC.readings = ["TC0F": 61]
        precondition(CPUTemperatureProbe.readSMC() == 61)
        SMC.readings = ["TC0P": .nan, "TC0D": 60]
        precondition(CPUTemperatureProbe.readSMC() == 60)
        print("PASS Intel dynamic API, live readings, failure recovery, sample release, optional library and SMC fallback")
    }
}
