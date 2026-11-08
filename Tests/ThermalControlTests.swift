import Foundation

// Exercise the real UI state controller without privileged hardware writes.
@MainActor final class FanControl {
    static let shared = FanControl()
    var selectedCode = "FX507ZM"
    var detection = (code: "FX507ZM", unused: false)
    var applying: String?
    var resetCount = 0
    var confirmedMode: ThermalMode?
    func noteFirmwarePolicyApplied() { resetCount += 1 }
    func synchronizeFirmwarePolicy(_ mode: ThermalMode?) { confirmedMode = mode }
}

final class ASUSWMIBridge {
    static let shared = ASUSWMIBridge()
    private let lock = NSLock()
    private var ready = true
    private var session: UInt64 = 0
    private var accepted: Int?
    private var blockRead = true
    private var readStarted = false
    let releaseRead = DispatchSemaphore(value: 0)
    var setupMessage: String { "控制驱动未就绪" }
    var hasChargeLimit: Bool { false }
    func chargeLimit() -> Int? { nil }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
    var thermalDevice: UInt32? { locked { ready ? 0x00120075 : nil } }
    var thermalSessionToken: UInt64? { locked { ready ? session : nil } }
    var hasStartedRead: Bool { locked { readStarted } }
    func thermalMode() -> Int? {
        let snapshot = locked { () -> (Int?, Bool) in
            let shouldBlock = blockRead
            blockRead = false
            if shouldBlock { readStarted = true }
            return (accepted, shouldBlock)
        }
        if snapshot.1 { releaseRead.wait() }
        return snapshot.0
    }
    func recordAcceptedThermalMode(_ mode: Int, session token: UInt64) -> Bool {
        locked {
            guard ready, token == session else { return false }
            accepted = mode
            return true
        }
    }
    func changeConnection(ready: Bool = true) {
        locked { self.ready = ready; session &+= 1; accepted = nil }
    }
}

final class ECFanBridge {
    static let shared = ECFanBridge()
    private(set) var accessCount = 0
    var isAvailable: Bool { accessCount += 1; return true }
    func thermalMode() -> Int? { accessCount += 1; return 0 }
    func setThermalMode(_ mode: Int) -> Bool { accessCount += 1; return true }
    func chargeLimit() -> Int? { nil }
    func setChargeLimit(_ percent: Int) -> Bool { false }
}

enum Admin {
    static var changeConnection = false
    static func runSelfAsAdmin(_ args: [String]) -> (ok: Bool, output: String) {
        if changeConnection { ASUSWMIBridge.shared.changeConnection() }
        return (true, "固件已接受设置")
    }
}

@main struct ThermalControlTests {
    @MainActor static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        fatalError("Timed out waiting for controller")
    }

    @MainActor static func main() async {
        let bridge = ASUSWMIBridge.shared
        let control = ThermalControl.shared
        await waitUntil { bridge.hasStartedRead }
        control.set(.boost)
        await waitUntil { control.applying == nil }
        precondition(control.mode == .boost, "Privileged CLI success must update the GUI connection")
        bridge.releaseRead.signal()
        try? await Task.sleep(nanoseconds: 100_000_000)
        precondition(control.mode == .boost, "An older refresh must not erase the accepted mode")
        control.refresh()
        try? await Task.sleep(nanoseconds: 50_000_000)
        precondition(control.mode == .boost, "Periodic refresh must retain boost")
        precondition(FanControl.shared.confirmedMode == .boost, "Factory fan policy follows the confirmed thermal mode")
        precondition(FanControl.shared.resetCount == 1, "A firmware policy change clears the old custom curve status")
        let session = bridge.thermalSessionToken!
        precondition(control.noteFanPresetApplied("silent", session: session))
        try? await Task.sleep(nanoseconds: 50_000_000)
        precondition(control.mode == .silent, "Fan preset and thermal controls must share the accepted mode")
        FanControl.shared.applying = "balanced"
        control.set(.boost)
        precondition(control.mode == .silent && control.applying == nil, "Prevent overlapping control writes")
        FanControl.shared.applying = nil

        Admin.changeConnection = true
        control.set(.balanced)
        await waitUntil { control.applying == nil }
        precondition(control.mode == nil, "A changed connection must invalidate the mode")
        try? await Task.sleep(nanoseconds: 50_000_000)
        precondition(FanControl.shared.confirmedMode == nil, "A changed connection must invalidate the factory fan policy")
        precondition(control.message?.contains("连接已改变") == true)
        Admin.changeConnection = false
        bridge.changeConnection(ready: false)
        control.refresh()
        await waitUntil { !control.available }
        control.set(.boost)
        await waitUntil { control.applying == nil }
        precondition(ECFanBridge.shared.accessCount == 0, "FX507ZM must never use legacy EC fallback")
        print("PASS: CLI acknowledgement, stale refresh, periodic refresh, connection invalidation, FX507ZM EC gate")
    }
}
