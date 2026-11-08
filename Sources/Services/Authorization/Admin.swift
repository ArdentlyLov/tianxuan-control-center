// Admin.swift

import Foundation

enum Admin {
    static var isRoot: Bool { geteuid() == 0 }

    /// 以管理员身份运行当前可执行文件的 CLI 模式
    static func runSelfAsAdmin(_ args: [String]) -> (ok: Bool, output: String) {
        if isRoot {
            return SelfExec.runCLI(args)
        }
        if SilentApply.isAuthorized {
            let result = runSilent(args)
            if result.ok { return result }
        }
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        func appleString(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let command = ([exe] + args).map { "(quoted form of \(appleString($0)))" }.joined(separator: " & \" \" & ")
        let script = "do shell script (\(command)) with administrator privileges"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (p.terminationStatus == 0, out)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// 静默以 root 执行本程序 CLI（不弹密码框）。
    /// 走 `sudo -n`：`-n` 表示非交互，一旦需要密码立即失败（不卡住、不弹框）。
    /// 调用方应把它当「能发就发，发不了就跳过」——典型用途是开机 / 唤醒的自动下发，
    /// 那时人不在场，弹密码框没有意义。手动点「应用」仍走 `runSelfAsAdmin`（弹框一次）。
    static func runSilent(_ args: [String]) -> (ok: Bool, output: String) {
        let exe = SilentApply.executionPath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", exe] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (p.terminationStatus == 0, out)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

/// 直接在本进程内执行 CLI 逻辑（已是 root 时走这里）
enum SelfExec {
    static func runCLI(_ args: [String]) -> (ok: Bool, output: String) {
        let status = CLI.run(args, printOutput: false)
        return (status == 0, CLI.lastMessage)
    }
}

