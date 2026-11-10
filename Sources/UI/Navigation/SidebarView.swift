import SwiftUI

struct SidebarView: View {
    @Binding var page: Page
    @EnvironmentObject var store: SensorStore
    @ObservedObject private var selection = SidebarSelection.shared
    @State private var hoveredPage: Page?
    @Namespace private var selectionNS
    private var displayPage: Page { selection.pending ?? page }
    private let groups: [(String, [Page])] = [
        ("设备", [.overview, .monitor, .network]),
        ("控制", [.performance, .keyboard, .nvidia]),
        ("工具", [.menubar, .advanced, .diagnostics, .about])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                TianxuanEmblem(height: 29)
                VStack(alignment: .leading, spacing: 5) {
                    Text("TIANXUAN")
                        .font(.system(size: 13, weight: .bold)).tracking(1.5)
                        .foregroundStyle(Palette.text)
                    Text("控制中心")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.horizontal, 22).padding(.top, 25).padding(.bottom, 27)
            .fixedSize(horizontal: false, vertical: true)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups.indices, id: \.self) { index in
                        Text(groups[index].0)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.leading, 24).padding(.top, index == 0 ? 0 : 18).padding(.bottom, 7)
                        ForEach(groups[index].1) { p in navRow(p) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 20)
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 9) {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.bottom, 5)
                HStack(spacing: 7) {
                    Circle().fill(store.smcReady ? Palette.ok : Palette.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(store.smcReady ? "AppleSMC 已连接" : "SMC 不可用")
                        .font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                }.padding(.horizontal, 10)
                Text("\(store.availableCount) / \(store.capabilities.count) 项能力可用")
                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 10)
                navRow(.settings).padding(.top, 5)
            }
            .padding(.horizontal, 12).padding(.bottom, 16)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 212)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.bgSoft)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.hairline).frame(width: 1) }
        .onChange(of: page) { newValue in
            if let p = selection.pending, p != newValue { selection.clearPending() }
        }
    }

    private func navRow(_ p: Page) -> some View {
        Button { selection.select(p) } label: {
            HStack(spacing: 11) {
                Image(systemName: p.icon)
                    .font(.system(size: 14, weight: .medium)).frame(width: 20)
                Text(p.title)
                    .font(.system(size: 12, weight: displayPage == p ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(displayPage == p ? Palette.accent : Palette.textSecondary)
            .padding(.horizontal, 12).frame(height: 38)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background {
                if displayPage == p {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.accent.opacity(0.10))
                        .matchedGeometryEffect(id: "selection", in: selectionNS)
                } else if hoveredPage == p {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.subtle)
                }
            }
        }
        .buttonStyle(.plain).padding(.horizontal, p == .settings ? 0 : 12)
        .padding(.vertical, 1)
        .onHover { hoveredPage = $0 ? p : nil }
        .help(p.title).accessibilityAddTraits(displayPage == p ? .isSelected : [])
    }
}
