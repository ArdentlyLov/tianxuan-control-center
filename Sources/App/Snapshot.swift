//
//  Snapshot.swift
//  离屏渲染界面快照（自检 / 文档配图用，不依赖截屏权限）
//    AsusControl snapshot <输出路径> [宽 高] [页面]
//  页面可选：overview / monitor / keyboard / performance / diagnostics / repairGuide
//

import SwiftUI
import AppKit

enum Snapshot {
    @MainActor
    static func render(to path: String, size: CGSize = CGSize(width: 1000, height: 730),
                       page: Page = .overview) -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        // 出图用的皮肤：ASUS_THEME=dark|light|tianxuan（默认天选简约）
        let envMode = ProcessInfo.processInfo.environment["ASUS_THEME"]
            .flatMap(ThemeMode.init(rawValue:)) ?? .tianxuan
        SkinFlag.tianxuan = (envMode == .tianxuan)
        app.appearance = NSAppearance(named: (envMode == .light || envMode == .tianxuan) ? .aqua : .darkAqua)

        // 和正常启动一样，在创建视图前完成控制器的同步机型探测。
        _ = FanControl.shared
        let store = SensorStore.shared
        store.start()                      // 先起引擎（内部会加载静态信息）
        store.overrideRate(.fast)          // 出图用 1 秒档，不写偏好
        store.setTilesActive(true)
        store.setProcessSamplingActive(true)
        // 给静态信息（机型/驱动/能力）留出加载时间；顺便积累几个采样点
        RunLoop.main.run(until: Date().addingTimeInterval(3.4))

        let content = windowView(store: store, page: page, size: size)
            .background(Palette.bg)
            // Settings / About 等页读 @EnvironmentObject theme，离屏渲染也要给一份
            .environmentObject(ThemeManager())
            // ImageRenderer 只认 SwiftUI 环境里的 colorScheme，不认 NSApp.appearance，
            // 动态 NSColor 的解析也会跟着它走 —— 不显式给一遍，深色会渲染成浅色。
            .environment(\.colorScheme, (envMode == .light || envMode == .tianxuan) ? .light : .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2.0
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            FileHandle.standardError.write(Data("写入失败: \(error)\n".utf8))
            return false
        }
    }

    @MainActor
    private static func windowView(store: SensorStore, page: Page, size: CGSize) -> some View {
        HStack(alignment: .top, spacing: 0) {
            SidebarView(page: .constant(page))
                .environmentObject(store)
                .frame(width: 212, height: size.height)
            VStack(alignment: .leading, spacing: 16) {
                switch page {
                case .overview: OverviewView()
                case .monitor: MonitorView()
                case .network: NetworkView()
                case .keyboard: KeyboardView()
                case .menubar: MenuBarSettingsView()
                case .performance: PerformanceView()
                case .nvidia: NvidiaView()
                case .diagnostics: DiagnosticsView()
                case .repairGuide: RepairGuideView()
                case .advanced: AdvancedView()
                case .settings: SettingsView()
                case .about: AboutView()
                }
            }
            .padding(24)
            .frame(width: size.width - 212, alignment: .leading)
            .background(Palette.bg)
        }
        .environmentObject(store)
    }
}
