// TianxuanControlApp.swift

import SwiftUI
import AppKit
import Combine

struct TianxuanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = SensorStore.shared
    @StateObject private var theme = ThemeManager()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(theme)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 730)
        // 必须是 `.unified`：系统按 toolbarStyle 决定窗口圆角，
        // `.unified` = 26pt（与 macOS 26 Safari 一致），`.unifiedCompact` 只有 20pt。
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("刷新全部 SMC 读数") { store.reloadAllReadings() }
            }
        }
    }
}

/// 菜单栏状态项里的单个指标：小图标 + 数值（不再显示文字标签）。
/// 预览（菜单栏设置页）传更大的字号即可复用，顺序/样式与真实状态栏一致。
