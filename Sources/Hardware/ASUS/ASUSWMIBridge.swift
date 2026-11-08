import Foundation
import IOKit

/// Firmware operations exposed by VelaAsusWMI.kext. No raw EC/MMIO access.
final class ASUSWMIBridge {
    static let shared = ASUSWMIBridge()
    static let serviceName = "VelaAsusWMI"
    static let missingDriverMessage = "天选控制驱动未加载。请使用协议 2 的 1.0.2 或 1.0.3 临时加载版驱动。"

    private let lock = NSRecursiveLock()
    private var connection: io_connect_t = 0
    private var selectedService: io_service_t = 0
    private var cachedProperties: [String: Any] = [:]
    private var lastRefresh = Date.distantPast
    private var thermalSession: UInt64 = 0
    private var acceptedThermalMode: Int?
    private(set) var lastError: String?

    private init() {}
    deinit { disconnectLocked() }

    private func propertiesLocked(_ service: io_service_t) -> [String: Any] {
        var properties: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS {
            return properties?.takeRetainedValue() as? [String: Any] ?? [:]
        }
        return [:]
    }

    // Returned service references belong to the caller. Enumeration never probes firmware.
    private func servicesLocked() -> [(service: io_service_t, properties: [String: Any])] {
        guard let matching = IOServiceMatching(Self.serviceName) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var services: [(service: io_service_t, properties: [String: Any])] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            let properties = propertiesLocked(service)
            guard ASUSWMIProtocol.servicePriority(properties) != nil else {
                IOObjectRelease(service)
                continue
            }
            services.append((service, properties))
        }
        return services.sorted {
            ASUSWMIProtocol.servicePriority($0.properties)! > ASUSWMIProtocol.servicePriority($1.properties)!
        }
    }

    private func activateLocked(_ service: io_service_t, properties: [String: Any]) -> Bool {
        if service != selectedService || connection == 0 {
            var opened: io_connect_t = 0
            let result = IOServiceOpen(service, mach_task_self_, 0, &opened)
            guard result == KERN_SUCCESS else {
                lastError = "无法连接天选控制驱动（0x\(String(UInt32(bitPattern: result), radix: 16))）"
                return false
            }
            disconnectLocked()
            IOObjectRetain(service)
            selectedService = service
            connection = opened
        }
        cachedProperties = properties
        lastRefresh = Date()
        lastError = nil
        return true
    }

    private func connectLocked() -> Bool {
        if connection != 0, Date().timeIntervalSince(lastRefresh) < 5 { return true }
        if connection != 0 {
            let properties = propertiesLocked(selectedService)
            // Refresh the properties of the opened provider, never an unrelated WMI service.
            if ASUSWMIProtocol.servicePriority(properties) == 2 {
                cachedProperties = properties
                lastRefresh = Date()
                return true
            }
        }
        let services = servicesLocked()
        defer { services.forEach { IOObjectRelease($0.service) } }
        for candidate in services {
            if activateLocked(candidate.service, properties: candidate.properties) { return true }
        }
        disconnectLocked()
        if services.isEmpty { lastError = Self.missingDriverMessage }
        return false
    }

    private func disconnectLocked() {
        if connection != 0 || selectedService != 0 { thermalSession &+= 1 }
        acceptedThermalMode = nil
        if connection != 0 { IOServiceClose(connection) }
        if selectedService != 0 { IOObjectRelease(selectedService) }
        connection = 0
        selectedService = 0
        cachedProperties = [:]
        lastRefresh = .distantPast
    }

    private func property(_ name: String) -> UInt32? {
        lock.lock(); defer { lock.unlock() }
        guard connectLocked(), let value = cachedProperties[name] as? NSNumber,
              value.uint32Value != 0 else { return nil }
        return value.uint32Value
    }

    var isAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        return connectLocked()
    }
    var firmwareReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return connectLocked() && (cachedProperties["FirmwareProbed"] as? NSNumber)?.boolValue == true
    }
    var setupMessage: String {
        guard isAvailable else { return lastError ?? Self.missingDriverMessage }
        return firmwareReady ? "本机固件未公开此控制功能" : "驱动已加载，等待手动读取固件接口。启动和打开应用不会自动探测固件。"
    }

    // Explicit user action only. Connecting to the service never performs this call.
    func probeFirmware() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let services = servicesLocked()
        defer { services.forEach { IOObjectRelease($0.service) } }
        guard !services.isEmpty else {
            lastError = Self.missingDriverMessage
            return false
        }
        var foundReady = false
        for candidate in services {
            guard activateLocked(candidate.service, properties: candidate.properties) else { continue }
            var output: UInt64 = 0, count: UInt32 = 1
            let result = IOConnectCallScalarMethod(connection, 4, nil, 0, &output, &count)
            cachedProperties = propertiesLocked(selectedService)
            if result == KERN_SUCCESS, count == 1, output == 1,
               let priority = ASUSWMIProtocol.servicePriority(cachedProperties), priority > 0 {
                foundReady = true
                if priority == 2 { return true }
            }
        }
        lastRefresh = .distantPast
        _ = connectLocked()
        if foundReady { return true }
        lastError = "手动读取固件失败：没有找到可用的华硕管理接口"
        return false
    }
    var thermalDevice: UInt32? { property("ThermalDevice") }
    var rgbDevice: UInt32? { property("RGBDevice") }
    private var secondaryRGBDevice: UInt32? { property("RGBSecondaryDevice") }
    var hasKeyboard: Bool { property("KeyboardDevice") != nil }
    var hasChargeLimit: Bool { property("ChargeDevice") != nil }
    var hasFanCurves: Bool { property("CPUCurveDevice") != nil && property("GPUCurveDevice") != nil }
    var fanCount: Int { (property("CPUFanDevice") == nil ? 0 : 1) + (property("GPUFanDevice") == nil ? 0 : 1) }

    func rawStatus(_ device: UInt32) -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() else { return nil }
        var input = UInt64(device), output: UInt64 = 0, count: UInt32 = 1
        let result = IOConnectCallScalarMethod(connection, 0, &input, 1, &output, &count)
        guard result == KERN_SUCCESS, count == 1 else {
            lastError = "读取华硕固件状态失败（0x\(String(UInt32(bitPattern: result), radix: 16))）"
            if result == kIOReturnNotOpen || result == kIOReturnNoDevice { disconnectLocked() }
            return nil
        }
        return output
    }

    @discardableResult
    private func write(_ device: UInt32, _ value: UInt64, _ extra: UInt64 = 0,
                       requireOne: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() else { return false }
        let input: [UInt64] = [UInt64(device), value, extra]
        var output: UInt64 = 0, count: UInt32 = 1
        let result = input.withUnsafeBufferPointer {
            IOConnectCallScalarMethod(connection, 1, $0.baseAddress, 3, &output, &count)
        }
        guard result == KERN_SUCCESS, count == 1, output <= 1, !requireOne || output == 1 else {
            lastError = result == kIOReturnNotPrivileged
                ? "修改华硕固件设置需要管理员授权"
                : "华硕固件没有接受设置（0x\(String(UInt32(bitPattern: result), radix: 16))，返回 \(output)）"
            if result == kIOReturnNotOpen || result == kIOReturnNoDevice { disconnectLocked() }
            return false
        }
        lastError = nil
        return true
    }

    func thermalMode() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard thermalDevice != nil else { return nil }
        // DSTS reports support/presence (e.g. 0x00010003), not the active policy.
        // Like asus-wmi, retain only a policy accepted during this connection.
        return acceptedThermalMode
    }
    var thermalSessionToken: UInt64? {
        lock.lock(); defer { lock.unlock() }
        guard thermalDevice != nil else { return nil }
        return thermalSession
    }
    @discardableResult
    func recordAcceptedThermalMode(_ mode: Int, session: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard (0...2).contains(mode), thermalDevice != nil, session == thermalSession else { return false }
        acceptedThermalMode = mode
        return true
    }
    func setThermalMode(_ mode: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard (0...2).contains(mode), let device = thermalDevice,
              write(device, UInt64(mode)) else { return false }
        acceptedThermalMode = mode
        return true
    }
    func rpm(cpu: Bool) -> Int? {
        guard let raw = rawStatus(cpu ? ASUSWMIProtocol.cpuFan : ASUSWMIProtocol.gpuFan) else { return nil }
        return ASUSWMIProtocol.rpm(raw)
    }
    func keyboardLevel() -> Int? {
        guard let raw = rawStatus(ASUSWMIProtocol.keyboard), let value = ASUSWMIProtocol.status(raw) else { return nil }
        let level = Int(value & 0x7F)
        return (0...3).contains(level) ? level : nil
    }
    func setKeyboardLevel(_ level: Int) -> Bool {
        guard (0...3).contains(level), hasKeyboard else { return false }
        return write(ASUSWMIProtocol.keyboard, UInt64(0x80 | level))
    }
    func chargeLimit() -> Int? {
        guard let raw = rawStatus(ASUSWMIProtocol.charge), let value = ASUSWMIProtocol.status(raw) else { return nil }
        let percent = Int(value & 0xFF)
        return (40...100).contains(percent) ? percent : nil
    }
    func setChargeLimit(_ percent: Int) -> Bool {
        let value = percent == 0 ? 100 : percent
        guard (40...100).contains(value), hasChargeLimit else { return false }
        return write(ASUSWMIProtocol.charge, UInt64(value))
    }
    func setRGB(mode: Int, red: Int, green: Int, blue: Int, speed: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let args = ASUSWMIProtocol.rgbArguments(mode: mode, red: red, green: green, blue: blue, speed: speed) else {
            lastError = "天选 FX507ZM 支持静态、呼吸、色彩循环和频闪四种单区灯效"
            return false
        }
        guard let device = rgbDevice else {
            lastError = isAvailable ? "本机固件未提供单区 RGB 控制接口" : Self.missingDriverMessage
            return false
        }
        // G-Helper: primary channel B4; older secondary channel B3 followed by B4.
        if device == ASUSWMIProtocol.rgb, write(device, args.0, args.1, requireOne: true) { return true }
        guard let secondary = secondaryRGBDevice,
              let staged = ASUSWMIProtocol.rgbArguments(mode: mode, red: red, green: green, blue: blue, speed: speed, save: false) else {
            return false
        }
        _ = write(secondary, staged.0, staged.1, requireOne: true)
        return write(secondary, args.0, args.1, requireOne: true)
    }

    func readCurve(cpu: Bool, mode: Int = 0) -> FanCurve? {
        guard let slot = ASUSWMIProtocol.curveSlot(thermalMode: mode) else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() else { return nil }
        let input: [UInt64] = [UInt64(cpu ? ASUSWMIProtocol.cpuCurve : ASUSWMIProtocol.gpuCurve), slot]
        var bytes = [UInt8](repeating: 0, count: 16), size = 16
        let result = input.withUnsafeBufferPointer { args in
            bytes.withUnsafeMutableBytes { buffer in
                IOConnectCallMethod(connection, 2, args.baseAddress, 2, nil, 0,
                                    nil, nil, buffer.baseAddress, &size)
            }
        }
        guard result == KERN_SUCCESS, size == 16 else { return nil }
        let curve = FanCurve(temp: bytes.prefix(8).map(Int.init), duty: bytes.suffix(8).map(Int.init))
        return curve.isValid ? curve : nil
    }

    func writeCurve(_ curve: FanCurve, cpu: Bool) -> Bool {
        guard let bytes = ASUSWMIProtocol.curveBytes(temps: curve.temp, duties: curve.duty) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() else { return false }
        var device = UInt64(cpu ? ASUSWMIProtocol.cpuCurve : ASUSWMIProtocol.gpuCurve)
        var output: UInt64 = 0, count: UInt32 = 1
        let result = bytes.withUnsafeBytes {
            IOConnectCallMethod(connection, 3, &device, 1, $0.baseAddress, bytes.count,
                                &output, &count, nil, nil)
        }
        guard result == KERN_SUCCESS, count == 1, output <= 1 else {
            lastError = "风扇曲线没有被固件接受（0x\(String(UInt32(bitPattern: result), radix: 16))，返回 \(output)）"
            return false
        }
        return true
    }

    var driverVersion: String? {
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() else { return nil }
        return cachedProperties["DriverVersion"] as? String
    }

    var diagnosticText: String {
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() else { return lastError ?? Self.missingDriverMessage }
        let version = cachedProperties["DriverVersion"] as? String ?? "未知版本"
        guard firmwareReady else { return "VelaAsusWMI \(version) 已加载；尚未读取固件。需要用户手动执行 wmi probe 或点击「读取固件接口」。" }
        return "VelaAsusWMI \(version)：性能 \(thermalDevice != nil)，键盘亮度 \(hasKeyboard)，RGB \(rgbDevice != nil)，风扇反馈 \(fanCount) 个，曲线 \(hasFanCurves)，充电上限 \(hasChargeLimit)"
    }
}
