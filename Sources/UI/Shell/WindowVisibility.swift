// WindowVisibility.swift

import SwiftUI
import AppKit
import Combine


/// 窗口可见性跟踪。
/// 将 AppKit 的可见性、缩放和最小化通知异步传给 SwiftUI，避免属性图重入。
final class WindowVisibility: ObservableObject {
    static let shared = WindowVisibility()

    @Published private(set) var isVisible = true

    /// 是否正在拖动边角缩放。
    @Published private(set) var isResizing = false

    /// 是否正在做最小化 / 还原到 Dock 的动画。
    /// 这段动画由窗口服务器 + GPU 合成，主线程整段阻塞在 `waitForTransaction` ——
    /// 没法多线程化。能做的只是少给它几层去合成（这台机的 Metal 是 Mesa nouveau
    /// 翻译层，genie 扭曲基本靠软件算，层越少越跟手）。
    @Published private(set) var isMinimizing = false

    /// 缩放或最小化过程中。
    var isBusy: Bool { isResizing || isMinimizing }

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var minimizeStartedAt: Date?
    /// 兜底轮询：某些路径（开机静默启动后自动收窗）不会发遮挡通知，
    /// 每秒纯属性检查一次即可，不参与任何 SwiftUI 刷新。
    private var poll: Timer?

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        let nc = NotificationCenter.default
        for o in observers { nc.removeObserver(o) }
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.willCloseNotification,
            NSWindow.willStartLiveResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.willMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]

        observers = names.map { name in
            nc.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                guard let self else { return }
                switch note.name {
                case NSWindow.willStartLiveResizeNotification: self.publish { $0.isResizing = true }
                case NSWindow.didEndLiveResizeNotification:   self.publish { $0.isResizing = false }
                case NSWindow.willMiniaturizeNotification:
                    self.publish { $0.isMinimizing = true }
                    self.minimizeStartedAt = Date()
                case NSWindow.didDeminiaturizeNotification:
                    self.publish { $0.isMinimizing = false }
                default: break
                }
                self.refresh()
            }
        }
        poll?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
        refresh()
    }

    /// ⚠️ 通知回调里绝不能**同步**改 `@Published`。
    ///
    /// AppKit 的遮挡 / 激活 / 最小化通知到达时，SwiftUI 自己也在这条通知里更新属性图
    /// （scenePhase、controlActiveState 都挂在同一批通知上）。我们同步发一次
    /// `objectWillChange`，就等于在属性图正在更新时又把它重入一次，AttributeGraph 直接
    /// `precondition_failure` → SIGABRT。实测：显示器睡眠后每次启动约 1.1s 必崩
    /// （崩溃栈：Dock 消息 → AppKit 通知 → SwiftUI → AG::Graph::value_set）。
    /// 统一推到下一拍改状态：语义上仍然是「通知来了立刻生效」，但躲开了重入。
    private func publish(_ apply: @escaping (WindowVisibility) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            apply(self)
        }
    }

    private func refresh() {
        guard let w = window else { return }
        let visible = w.isVisible
            && !w.isMiniaturized
            && w.occlusionState.contains(.visible)
        if visible != isVisible { publish { $0.isVisible = visible } }

        // 兜底：动画被打断（没等到 deminiaturize 通知）时别让装饰层一直缺席。
        // 用超时判断而不是 isMiniaturized —— 动画进行中该值还没翻转，会误清。
        if isMinimizing, let t = minimizeStartedAt, Date().timeIntervalSince(t) > 1.6,
           w.isVisible, !w.isMiniaturized {
            publish { $0.isMinimizing = false }
        }
    }
}
