import Foundation

/// ASUS management WMI protocol, shared by the CLI, UI and packet tests.
/// References: Linux asus-wmi.c and G-Helper AsusACPI.cs / Aura.cs.
enum ASUSWMIProtocol {
    // Both releases expose the same user-client protocol. Earlier drivers are incompatible.
    static func servicePriority(_ properties: [String: Any]) -> Int? {
        guard (properties["ProtocolVersion"] as? NSNumber)?.intValue == 2,
              let version = properties["DriverVersion"] as? String,
              ["1.0.2", "1.0.3"].contains(version) else { return nil }
        guard (properties["FirmwareProbed"] as? NSNumber)?.boolValue == true else { return 0 }
        return ((properties["ThermalDevice"] as? NSNumber)?.uint32Value ?? 0) != 0 ? 2 : 1
    }

    static let presence: UInt32 = 0x00010000
    static let thermalPolicy: UInt32 = 0x00120075
    static let fanBoost: UInt32 = 0x00110018
    static let keyboard: UInt32 = 0x00050021
    static let cpuFan: UInt32 = 0x00110013
    static let gpuFan: UInt32 = 0x00110014
    static let cpuCurve: UInt32 = 0x00110024
    static let gpuCurve: UInt32 = 0x00110025
    static let rgb: UInt32 = 0x00100056
    static let rgb2: UInt32 = 0x0010005A
    static let charge: UInt32 = 0x00120057
    static let rgbModes: Set<Int> = [0, 1, 2, 10]

    static func status(_ raw: UInt64) -> UInt32? {
        guard raw <= UInt32.max else { return nil }
        let value = UInt32(raw)
        guard value != 0xFFFFFFFE, value != 0xFFFFFFFF,
              value & presence != 0 else { return nil }
        return value & 0xFFFF
    }

    static func rpm(_ raw: UInt64) -> Int? {
        guard let value = status(raw) else { return nil }
        // ASUS fan feedback is in units of 100 RPM, including zero-RPM idle.
        let result = Int(value & 0xFF) * 100
        return result <= 12000 ? result : nil
    }

    static func curveSlot(thermalMode: Int) -> UInt64? {
        switch thermalMode {
        case 0: return 0
        case 1: return 2
        case 2: return 1
        default: return nil
        }
    }

    static func curveBytes(temps: [Int], duties: [Int]) -> [UInt8]? {
        guard temps.count == 8, duties.count == 8,
              temps.allSatisfy({ (20...110).contains($0) }),
              duties.allSatisfy({ (0...100).contains($0) }),
              zip(temps, temps.dropFirst()).allSatisfy({ $0 <= $1 }),
              zip(duties, duties.dropFirst()).allSatisfy({ $0 <= $1 }) else { return nil }
        return (temps + duties).map(UInt8.init)
    }

    static func rgbArguments(mode: Int, red: Int, green: Int, blue: Int,
                             speed: Int, save: Bool = true) -> (UInt64, UInt64)? {
        // FX507ZM has a single lighting zone and these four basic effects.
        guard rgbModes.contains(mode), [red, green, blue].allSatisfy({ (0...255).contains($0) }),
              [0xE1, 0xEB, 0xF5].contains(speed) else { return nil }
        let first = UInt64(save ? 0xB4 : 0xB3) | UInt64(mode) << 8 |
                    UInt64(red) << 16 | UInt64(green) << 24
        let second = UInt64(blue) | UInt64(speed) << 8
        return (first, second)
    }
}
