// AppDelegate.swift

import SwiftUI
import AppKit
import Combine

/// 自检：设置 ASUS_SELFTEST=1 启动时，把自身窗口内容渲染成 PNG 后退出。
/// 用途：在没有「屏幕录制」权限的环境里验证界面是否真的画出来了。
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 自己管理的菜单栏状态项（替代 MenuBarExtra，便于精确控制字号）
    private let statusBar = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isSelfTest = ProcessInfo.processInfo.environment["ASUS_SELFTEST"] != nil
        // 菜单栏状态项：图标 + 数值（字号完全可控）
        statusBar.start()
        // 改过 App 名字 / 换过安装位置时，把开机自启的 LaunchAgent 指到新路径
        // （先迁 label：AsusControl 时期用的是 dev.asuscontrol.mac.autostart）
        if !isSelfTest {
            LaunchAtLogin.migrateLegacyLabel()
            LaunchAtLogin.repairIfMoved()
        }
        // 「开机自动应用配置」的规则补装要放后台（下面那段 async 里做）：
        // 它会弹一次管理员密码框，同步跑在启动流程里会把窗口冻住。
        // 睡眠唤醒后 EC 会把功耗墙 / 风扇曲线重置，重新静默下发一遍
        NotificationCenter.default.addObserver(
            self, selector: #selector(onWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        // 由开机自启拉起时只驻留菜单栏：SwiftUI 的 WindowGroup 默认会给一个窗口，
        // 这里在它建好之后收起来，避免登录时突然弹一个窗口。
        if !isSelfTest && LaunchAtLogin.isAutostartLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                for w in NSApp.windows where w.frame.width > 600 {
                    w.orderOut(nil)
                }
            }
        }

        // 外观由 ThemeManager 决定（默认天选简约，可切浅色 / 跟随系统）
        // 开机 / 唤醒自动下发功耗墙 + 风扇：仅正常启动执行，自检模式不动硬件。
        // 全程在后台线程：规则失效时先补装（必要时弹一次密码框），装好立刻补发一次；
        // 启动初期 kext / SMC 可能还没完全就绪，稍等再发，失败再重试一轮。
        if !isSelfTest {
            DispatchQueue.global(qos: .utility).async {
                SilentApply.repairIfNeeded()
                Thread.sleep(forTimeInterval: 2.0)
                if !SilentApply.applyCurrentConfig() {
                    Thread.sleep(forTimeInterval: 6.0)
                    SilentApply.applyCurrentConfig()
                }
            }
        }




        guard isSelfTest else { return }
        setbuf(stdout, nil)   // 自测输出不缓冲，崩溃时也能看到进度
        // 默认等 4 秒。机器慢的时候 4 秒只够采一轮，网速和 CPU 占用率
        // 都要两次采样才有值，截图上会显示成「—」，看着像坏了。用
        // ASUS_SELFTEST_DELAY 把等待时间调长即可。
        let delay = Double(ProcessInfo.processInfo.environment["ASUS_SELFTEST_DELAY"] ?? "") ?? 4.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // 取主窗口（宽 > 600 的那个），避免抓到菜单栏那个几十像素宽的状态项窗口
            let window = NSApp.windows
                .filter { $0.contentView != nil && $0.frame.width > 600 }
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            // 抓「窗口真实合成结果」：CGWindowListCreateImage 抓的是窗口服务器合成后的画面，
            // 包含透明、圆角、behindWindow 玻璃，比 cacheDisplay/layer.render 更接近真机观感。
            if let window {
                if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                    CGWindowID(window.windowNumber),
                                                    [.boundsIgnoreFraming, .bestResolution]) {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: "/tmp/live_window.png"))
                } else if let view = window.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    // 兜底：该 API 不可用时退回离屏渲染（会丢 ScrollView 内容，仅供粗看）
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: "/tmp/live_window.png"))
                    }
                }
            }
            // 自测顺带输出窗口外观状态，便于确认「26pt 圆角 + 顶栏同源背景」是否到位
            if let window {
                let tf = window.contentView?.superview
                print("[selftest] toolbar=\(window.toolbar != nil) style=\(window.toolbarStyle.rawValue) "
                      + "cornerRadius=\(tf?.value(forKey: "cornerRadius") ?? "nil") "
                      + "themeFrame=\(tf?.bounds.size ?? .zero) contentView=\(window.contentView?.bounds.size ?? .zero)")
            }
            NSApp.terminate(nil)
        }
    }

    /// 睡眠唤醒后 EC 重置功耗墙 / 风扇曲线，重新静默下发一遍。
    /// 唤醒后硬件（kext / SMC）需一点时间重新就绪，稍等再发；未启用 / 未授权时内部跳过。
    @objc private func onWake() {
        guard ProcessInfo.processInfo.environment["ASUS_SELFTEST"] == nil else { return }
        guard SilentApply.isEnabled else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) {
            SilentApply.applyCurrentConfig()
        }
    }

}
