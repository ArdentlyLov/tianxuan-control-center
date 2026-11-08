// ScrollerAutoHide.swift

import SwiftUI
import AppKit
import Combine

/// 让底层 NSScrollView 的滚动条采用 overlay 浮层风格，并在空闲时自动隐藏。
/// 无论系统「滚动条」偏好是「始终」还是「滚动时」，右侧那条滚动条都只在滚动时
/// 短暂浮出、平时隐藏，避免常驻条破坏 Liquid Glass 的沉浸观感。
struct ScrollerAutoHide: NSViewRepresentable {
    /// 只配置一次的占位视图：updateNSView 每秒都会被调一次，
    /// 每次都往主队列塞一个 async 纯属白开销。
    final class Once: NSView {
        var done = false
    }

    func makeNSView(context: Context) -> NSView { Once() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let once = nsView as? Once, !once.done else { return }
        DispatchQueue.main.async {
            guard !once.done, let sv = nsView.enclosingScrollView else { return }
            sv.scrollerStyle = .overlay
            sv.autohidesScrollers = true
            sv.verticalScroller?.scrollerStyle = .overlay
            sv.horizontalScroller?.scrollerStyle = .overlay
            once.done = true
        }
    }
}

