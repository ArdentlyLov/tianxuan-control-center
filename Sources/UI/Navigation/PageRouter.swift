// PageRouter.swift

import SwiftUI
import AppKit
import Combine

enum Page: String, CaseIterable, Identifiable {
    case overview, monitor, network, menubar, keyboard, performance, nvidia, advanced, diagnostics, settings, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "概览"
        case .monitor: return "监控"
        case .network: return "网络"
        case .keyboard: return "键盘背光"
        case .menubar: return "菜单栏"
        case .performance: return "性能与风扇"
        case .nvidia: return "NVIDIA 驱动"
        case .diagnostics: return "诊断"
        case .advanced: return "高级功能"
        case .settings: return "设置"
        case .about: return "关于"
        }
    }
    /// （总控台 = 概览、观测站 = 监控、通信链路 = 网络…），悬停还会显示原名。
    var tianxuanTitle: String { title }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .monitor: return "waveform.path.ecg"
        case .network: return "network"
        case .keyboard: return "keyboard"
        case .menubar: return "menubar.dock.rectangle"
        case .performance: return "fanblades"
        case .nvidia: return "display"
        case .diagnostics: return "stethoscope"
        case .advanced: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

/// 当前页面。做成共享对象，这样菜单栏弹窗里的「去设置」也能把主窗口切到指定页
final class PageRouter: ObservableObject {
    static let shared = PageRouter()

    /// 正在显示的页
    @Published var page: Page =
        Page(rawValue: ProcessInfo.processInfo.environment["ASUS_PAGE"] ?? "") ?? .overview

    /// 立即切页（菜单栏跳转等，不走动画）
    func jump(to p: Page) {
        guard p != page else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { page = p }
        SidebarSelection.shared.clearPending()
    }
}

/// 侧栏「高亮先行」的选中状态。
///
/// 单独一个对象、只被 `SidebarView` 订阅 —— 若把它塞进 `PageRouter`，
/// 点一下就会让 `ContentView`（整页内容）跟着失效，多一次整窗重排。
final class SidebarSelection: ObservableObject {
    static let shared = SidebarSelection()

    /// 预选页：玻璃先滑过去，内容等滑动结束再换
    @Published private(set) var pending: Page?

    /// 滑动节奏（0.36 → 0.24 → 0.16 → 0.13：越短越像「指哪打哪」）
    static let spring = Animation.spring(response: 0.13, dampingFraction: 0.92)
    /// 高亮滑完到换内容的间隔。必须 ≥ 弹簧时长，否则重建页面的那几十毫秒会盖在动画上。
    static let swapDelay: Double = 0.15

    private var work: DispatchWorkItem?
    private init() {}

    /// 切页：高亮立刻动，内容稍后换。
    ///
    /// 换页要重建新页整棵树（实测一页约 50ms，两个重页互切 100ms+），这段时间主线程
    /// 被完全占住。若和高亮滑动塞进同一个事务，玻璃会卡在半路「一跳一跳」——
    /// 这就是「侧边栏切换明显掉帧」的来源。所以把换内容推迟到滑动结束之后。
    func select(_ p: Page) {
        let current = PageRouter.shared.page

        // 点回「当前正在显示的页」：撤销还没生效的预选，否则到点还是会跳走
        if p == current {
            work?.cancel()
            if pending != nil { withAnimation(Self.spring) { pending = nil } }
            return
        }
        guard pending != p else { return }

        withAnimation(Self.spring) { pending = p }

        work?.cancel()
        let job = DispatchWorkItem { [weak self] in
            guard let self, self.pending == p else { return }
            // 内容本身不带动画：新页整棵树弹簧入场会让每一帧都重排一次
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { PageRouter.shared.page = p }
            self.pending = nil
        }
        work = job
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.swapDelay, execute: job)
    }

    func clearPending() { pending = nil }
}

