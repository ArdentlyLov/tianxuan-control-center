import Foundation

// Platform discovery is replaced only at its I/O boundary. Scoring and packet code are production files.
enum SystemProbe {
    static func fingerprint() -> HardwareFingerprint { HardwareFingerprint() }
    static func ioregString(_ service: String, _ key: String) -> String? { nil }
}

@main
struct HardwareTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fatalError("FAILED: \(label)") }
            checks += 1
        }
        func detection(cpu: String, gpu: String) -> ModelDetection {
            var fp = HardwareFingerprint()
            fp.cpu = cpu; fp.cpuCode = HardwareIdentity.cpuCode(from: cpu); fp.gpus = [gpu]
            let scores = ECProfiles.catalog.map { ModelDetector.score(profile: $0, fingerprint: fp) }
                .filter { $0.points > 0 }.sorted { $0.points > $1.points }
            return ModelDetection(fingerprint: fp, scores: scores)
        }
        check(HardwareIdentity.cpuCode(from: "12th Gen Intel(R) Core(TM) i7-12700H") == "12700H", "Intel five-digit CPU")
        check(HardwareIdentity.cpuCode(from: "AMD Ryzen 9 6900HX with Radeon Graphics") == "6900HX", "AMD CPU")
        check(HardwareIdentity.cpuCode(from: "Intel Core Ultra 9 275HX") == "275HX", "Core Ultra CPU")
        check(HardwareIdentity.cpuCode(from: "Unknown CPU").isEmpty, "missing CPU")
        let tuf = detection(cpu: "12th Gen Intel(R) Core(TM) i7-12700H", gpu: "NVIDIA GeForce RTX 3060 Laptop GPU")
        check(tuf.code == "FX507ZM" && tuf.confidence == .high, "FX507ZM identity")
        check(detection(cpu: "AMD Ryzen 9 6900HX", gpu: "RTX 3060 Laptop GPU").code == "G513RM", "retain AMD model")
        check(detection(cpu: "", gpu: "RTX 3060").code == "UNKNOWN", "GPU alone cannot select EC profile")
        check(detection(cpu: "Intel i7-12700H", gpu: "RTX 3070").code == "UNKNOWN", "wrong GPU")
        check(detection(cpu: "Intel i7-12700HX", gpu: "RTX 3060").code == "UNKNOWN", "wrong CPU suffix")
        check(ECProfiles.match("FX507ZM").level == .verified, "exact profile")
        check(ECProfiles.match("FX").level == .unknown, "short prefix must not match")
        check(ECProfiles.match("FX507ZV").level == .unknown, "different TUF generation")
        let unprobed: [String: Any] = ["ProtocolVersion": 2, "DriverVersion": "1.0.3", "FirmwareProbed": false, "ThermalDevice": 0]
        var ready = unprobed
        ready["FirmwareProbed"] = true
        ready["ThermalDevice"] = ASUSWMIProtocol.thermalPolicy
        check(ASUSWMIProtocol.servicePriority(unprobed) == 0, "live 1.0.3 protocol compatibility")
        check(ASUSWMIProtocol.servicePriority(ready) == 2, "thermal management provider priority")
        let providers = [unprobed, unprobed, ready].sorted {
            ASUSWMIProtocol.servicePriority($0)! > ASUSWMIProtocol.servicePriority($1)!
        }
        check((providers.first?["ThermalDevice"] as? NSNumber)?.uint32Value == ASUSWMIProtocol.thermalPolicy,
              "select working third provider instead of first unrelated provider")
        for version in ["1.0.0", "1.0.1", "1.0.4"] {
            var incompatible = ready; incompatible["DriverVersion"] = version
            check(ASUSWMIProtocol.servicePriority(incompatible) == nil, "reject incompatible driver \(version)")
        }
        var previous = ready; previous["DriverVersion"] = "1.0.2"
        check(ASUSWMIProtocol.servicePriority(previous) == 2, "retain 1.0.2 compatibility")
        previous["ProtocolVersion"] = 1
        check(ASUSWMIProtocol.servicePriority(previous) == nil, "reject incompatible user-client protocol")
        check(ASUSWMIProtocol.status(0xFFFFFFFE) == nil, "unsupported status")
        check(ASUSWMIProtocol.status(0xFFFFFFFF) == nil, "invalid status")
        check(ASUSWMIProtocol.status(0x00000002) == nil, "presence bit required")
        check(ASUSWMIProtocol.rpm(0x0001002A) == 4200, "firmware RPM units")
        check(ASUSWMIProtocol.rpm(0x00010000) == 0, "stopped fan is valid")
        check(ASUSWMIProtocol.rpm(0x000100FF) == nil, "invalid RPM")
        check(ASUSWMIProtocol.curveSlot(thermalMode: 2) == 1, "silent curve slot")
        check(ASUSWMIProtocol.curveSlot(thermalMode: 1) == 2, "boost curve slot")
        check(ASUSWMIProtocol.curveSlot(thermalMode: 3) == nil, "invalid mode")
        let packet = ASUSWMIProtocol.rgbArguments(mode: 1, red: 255, green: 64, blue: 32, speed: 0xEB)
        check(packet?.0 == 0x40FF01B4 && packet?.1 == 0xEB20, "TUF primary RGB apply packet")
        let staged = ASUSWMIProtocol.rgbArguments(mode: 1, red: 255, green: 64, blue: 32, speed: 0xEB, save: false)
        check(staged?.0 == 0x40FF01B3 && staged?.1 == 0xEB20, "TUF secondary RGB staging packet")
        check(ASUSWMIProtocol.rgbArguments(mode: 10, red: 255, green: 255, blue: 255, speed: 0xF5)?.0 == 0xFFFF0AB4, "single-zone strobe")
        check(ASUSWMIProtocol.rgbArguments(mode: 3, red: 0, green: 0, blue: 0, speed: 0xEB) == nil, "single-zone keyboard has no rainbow")
        check(ASUSWMIProtocol.rgbArguments(mode: 0, red: 0, green: 0, blue: 0, speed: 1) == nil, "invalid lighting speed")
        check(ASUSWMIProtocol.rgbArguments(mode: 12, red: 0, green: 0, blue: 0, speed: 0xEB) == nil, "unsupported lighting effect")
        check(ASUSWMIProtocol.rgbArguments(mode: 0, red: 256, green: 0, blue: 0, speed: 0xEB) == nil, "out-of-range colour")
        let temps = [30,40,50,60,70,80,90,100], duties = [0,10,20,30,40,60,80,100]
        check(ASUSWMIProtocol.curveBytes(temps: temps, duties: duties)?.count == 16, "curve encoding")
        check(ASUSWMIProtocol.curveBytes(temps: temps, duties: [-1,10,20,30,40,60,80,100]) == nil, "negative duty")
        check(ASUSWMIProtocol.curveBytes(temps: [30,40,50,49,70,80,90,100], duties: duties) == nil, "descending temperature")
        check(ASUSWMIProtocol.curveBytes(temps: [30,40], duties: duties) == nil, "truncated curve")
        print("PASS: \(checks) hardware identity and WMI packet checks")
    }
}
