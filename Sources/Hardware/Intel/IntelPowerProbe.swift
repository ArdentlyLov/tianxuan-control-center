import Foundation
import Darwin

/// Optional Intel Power Gadget API. Reads EnergyDriver without root privileges.
/// Effective frequency and package power are differences between two samples.
final class IntelPowerProbe {
    static let shared = IntelPowerProbe()

    struct Sample {
        var temperature: Double?
        var powerWatts: Double?
        var avgFreqGHz: Double?
        var maxFreqGHz: Double?
    }

    private typealias Initialize = @convention(c) () -> Bool
    private typealias PackageCount = @convention(c) (UnsafeMutablePointer<Int32>) -> Bool
    private typealias Read = @convention(c) (Int32, UnsafeMutablePointer<UInt64>) -> Bool
    private typealias Release = @convention(c) (UInt64) -> Bool
    private typealias Temperature = @convention(c) (UInt64, UnsafeMutablePointer<Double>) -> Bool
    private typealias Power = @convention(c) (UInt64, UInt64, UnsafeMutablePointer<Double>, UnsafeMutablePointer<Double>) -> Bool
    private typealias Frequency = @convention(c) (UInt64, UInt64, UnsafeMutablePointer<Double>, UnsafeMutablePointer<Double>, UnsafeMutablePointer<Double>) -> Bool

    private struct API {
        let shutdown: Initialize
        let read: Read
        let release: Release
        let temperature: Temperature
        let power: Power
        let frequency: Frequency
    }

    private let lock = NSLock()
    private var library: UnsafeMutableRawPointer?
    private var api: API?
    private var previous: UInt64?
    private var previousTime: TimeInterval?
    var available: Bool { api != nil }

    init(libraryPath: String = "/Library/Frameworks/IntelPowerGadget.framework/Versions/A/IntelPowerGadget") {
        #if arch(x86_64)
        guard let handle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else { return }
        func symbol<T>(_ name: String, _: T.Type) -> T? {
            guard let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        guard let initialize = symbol("PG_Initialize", Initialize.self),
              let shutdown = symbol("PG_Shutdown", Initialize.self),
              let count = symbol("PG_GetNumPackages", PackageCount.self),
              let read = symbol("PG_ReadSample", Read.self),
              let release = symbol("PGSample_Release", Release.self),
              let temperature = symbol("PGSample_GetPackageTemperature", Temperature.self),
              let power = symbol("PGSample_GetPackagePower", Power.self),
              let frequency = symbol("PGSample_GetIAFrequency", Frequency.self) else {
            dlclose(handle)
            return
        }
        guard initialize() else { dlclose(handle); return }
        var packages: Int32 = 0
        var first: UInt64 = 0
        guard count(&packages), packages > 0, read(0, &first) else {
            _ = shutdown()
            dlclose(handle)
            return
        }
        library = handle
        api = API(shutdown: shutdown, read: read, release: release,
                  temperature: temperature, power: power, frequency: frequency)
        previous = first
        previousTime = ProcessInfo.processInfo.systemUptime
        #endif
    }

    deinit {
        if let api {
            if let previous { _ = api.release(previous) }
            _ = api.shutdown()
        }
        if let library { dlclose(library) }
    }

    func sample() -> Sample {
        lock.lock(); defer { lock.unlock() }
        guard let api else { return Sample() }
        var current: UInt64 = 0
        guard api.read(0, &current) else { return Sample() }
        let now = ProcessInfo.processInfo.systemUptime
        defer {
            if let previous { _ = api.release(previous) }
            previous = current
            previousTime = now
        }
        var result = Sample()
        var temperature = 0.0
        if api.temperature(current, &temperature), temperature.isFinite, (1...125).contains(temperature) {
            result.temperature = temperature
        }
        // Re-prime after sleep; an average over the sleep interval is not a live value.
        guard let previous, let previousTime, now - previousTime <= 15 else { return result }
        var watts = 0.0, joules = 0.0
        if api.power(previous, current, &watts, &joules), watts.isFinite, (0...1000).contains(watts) {
            result.powerWatts = watts
        }
        var mhz = 0.0, minimum = 0.0, maximum = 0.0
        if api.frequency(previous, current, &mhz, &minimum, &maximum) {
            if mhz.isFinite, mhz > 0, mhz <= 10000 { result.avgFreqGHz = mhz / 1000 }
            if maximum.isFinite, maximum > 0, maximum <= 10000 { result.maxFreqGHz = maximum / 1000 }
        }
        return result
    }
}

enum CPUTemperatureProbe {
    static let keys = ["TC0P", "TC0F", "TC0D", "TC0E"]
    static var smcAvailable: Bool { keys.contains { SMC.exists($0) } }

    static func readSMC() -> Double? {
        for key in keys {
            if let value = SMC.read(key)?.number, value.isFinite, (1...125).contains(value) {
                return value
            }
        }
        return nil
    }
}
