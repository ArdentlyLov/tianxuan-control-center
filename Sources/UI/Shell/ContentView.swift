import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: SensorStore
    @EnvironmentObject var theme: ThemeManager
    @StateObject private var router = PageRouter.shared
    @State private var pageReady = false
    var body: some View {
        HStack(spacing: 0) {
            SidebarView(page: $router.page)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("pageTop")
                        VStack(alignment: .leading, spacing: 16) {
                            if pageReady {
                                switch router.page {
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
                            } else { Color.clear.frame(height: 1) }
                        }
                        .padding(24).frame(maxWidth: 960, alignment: .leading)
                        .frame(maxWidth: .infinity).background(ScrollerAutoHide())
                    }
                }
                .id(router.page)
                .modifier(TianxuanScrollEdgeOff())
                .onChange(of: pageReady) { ready in
                    guard ready else { return }
                    DispatchQueue.main.async { proxy.scrollTo("pageTop", anchor: .top) }
                }
                .onChange(of: router.page) { _ in
                    DispatchQueue.main.async { proxy.scrollTo("pageTop", anchor: .top) }
                }
            }
        }
        .id(theme.mode)
        .background { WorkspaceBackground().ignoresSafeArea() }
        .overlay(WindowAccessor())
        .tint(Palette.accent)
        .preferredColorScheme(theme.mode.colorScheme)
        .onAppear {
            store.start()
            theme.applyAppearance()
            // Keep AppKit's initial visibility notifications outside the first page layout.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { pageReady = true }
        }
    }
}
