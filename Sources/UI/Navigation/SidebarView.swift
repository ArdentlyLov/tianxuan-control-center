import SwiftUI

struct SidebarView: View {
    @Binding var page: Page
    @EnvironmentObject var store: SensorStore
    @ObservedObject private var selection = SidebarSelection.shared
    @Namespace private var selectionNS
    private var displayPage: Page { selection.pending ?? page }
    private let groups: [(String, [Page])] = [
        ("设备", [.overview, .monitor, .network]),
        ("控制", [.performance, .keyboard, .nvidia]),
        ("工具", [.menubar, .advanced, .diagnostics, .about])
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                TianxuanEmblem(height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("天选").font(.system(size: 23, weight: .black)).tracking(3)
                        .foregroundStyle(Palette.text)
                    Text("CONTROL CENTER").font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1).foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 24)
            ForEach(groups.indices, id: \.self) { index in
                Text(groups[index].0).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.leading, 24).padding(.top, index == 0 ? 0 : 15).padding(.bottom, 6)
                ForEach(groups[index].1) { p in navRow(p) }
            }
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(store.smcReady ? Palette.ok : Palette.textTertiary).frame(width: 5, height: 5)
                    Text(store.smcReady ? "AppleSMC 已连接" : "SMC 不可用")
                        .font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                }
                Text("\(store.availableCount) / \(store.capabilities.count) 项能力可用")
                    .font(.system(size: 9)).foregroundStyle(Palette.textTertiary)
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.vertical, 4)
                navRow(.settings)
            }.padding(.horizontal, 12).padding(.bottom, 16)
        }
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.bgSoft.opacity(0.72))
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.hairline).frame(width: 1) }
        .onChange(of: page) { newValue in
            if let p = selection.pending, p != newValue { selection.clearPending() }
        }
    }
    private func navRow(_ p: Page) -> some View {
        Button { selection.select(p) } label: {
            HStack(spacing: 10) {
                Image(systemName: p.icon).font(.system(size: 14, weight: .medium)).frame(width: 19)
                    .foregroundStyle(displayPage == p ? Palette.accent : Palette.textSecondary)
                Text(p.title).font(.system(size: 12, weight: displayPage == p ? .semibold : .regular))
                    .foregroundStyle(displayPage == p ? Palette.text : Palette.textSecondary)
                Spacer(minLength: 0)
                if displayPage == p {
                    Rectangle().fill(Palette.accent).frame(width: 3, height: 12)
                }
            }
            .padding(.horizontal, 12).frame(height: 35)
            .contentShape(Rectangle())
            .background {
                if displayPage == p {
                    PanelShape(cut: 8).fill(Palette.accent.opacity(0.10))
                        .matchedGeometryEffect(id: "selection", in: selectionNS)
                }
            }
        }
        .buttonStyle(.plain).padding(.horizontal, p == .settings ? 0 : 12)
        .help(p.title).accessibilityAddTraits(displayPage == p ? .isSelected : [])
    }
}
