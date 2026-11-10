// OverviewView.swift

import SwiftUI
import AppKit
import Combine

// MARK: - 概览

struct OverviewView: View {
    @EnvironmentObject var store: SensorStore
    /// 全量顺序（含被隐藏的卡）；显示时再过滤。这样拖拽排序后存回去不会把隐藏项弄丢。
    @State private var cards: [OverviewCard] = OverviewLayoutPrefs.order
    @State private var hidden: Set<OverviewCard> = OverviewLayoutPrefs.hidden
    /// 正在拖拽的卡片（拖拽排序用）。
    /// 必须是 @GestureState 而不是 @State：实时重排时若被拖卡片跨行，它所在的 ForEach 会先移除、
    /// 再插到另一行，原 View 被销毁导致系统直接「取消」手势、onEnded 不再触发；
    /// @State 就会永久停在「放大中」，表现为松手后那张卡大一圈、必须切页才恢复。
    /// @GestureState 由手势自身持有，手势结束或被取消都会自动复位为 nil。
    @GestureState private var draggingCard: OverviewCard?
    /// 本次拖拽的「源卡片」：手势期间锁存，避免卡片让位后按起始坐标认错。
    /// 只用于逻辑判断；视觉（抬起/缩回）一律由上面的 @GestureState 驱动。
    @State private var dragSource: OverviewCard?
    /// 各卡片在全局坐标系下的 frame，松手时用来判断落在哪张卡上
    @State private var dragFrames: [OverviewCard: CGRect] = [:]
    /// 编辑模式（iOS 小组件式）：开 = 窗口固定、卡片可拖/可增删；关 = 窗口可拖、卡片固定。
    @ObservedObject private var windowState = WindowState.shared

    /// 辅助卡片统一高度，保证两两并排时对齐。
    private let smallCardHeight: CGFloat = 144

    private var visibleCards: [OverviewCard] { cards.filter { !hidden.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if visibleCards.isEmpty {
                emptyHint
            } else {
                // LazyVStack：切进这一页时只构建可见的几行，屏幕外的卡不参与
                // 视图树构建 —— 切页耗时与视图数量成正比，这一条能省掉近一半。
                LazyVStack(spacing: 12) {
                    ForEach(Array(cardRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 12) {
                            ForEach(row) { card in
                                cardSlot(card)
                            }
                            // 落单的窄卡：补一个等宽透明占位，让它保持半宽。
                            // 否则同一张窄卡「旁边有伴=半宽、落单=整行」会随拖拽位置变宽变窄，
                            // 造成保存后卡片大小不一致。
                            if row.count == 1, let only = row.first, !only.isWide {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                // 手势挂在「卡片网格」这一层，而不是每张卡自己身上。
                // 卡片实时让位时若跨行，它会被从 A 行的 ForEach 移除、插到 B 行 → 原 View 销毁 →
                // 挂在它上面的手势被系统取消（onEnded 不再触发），表现为拖到一半就断。
                // 容器在整个拖拽过程中一直存在，手势不会被中途掐掉。
                .gesture(windowState.isEditMode ? gridDragGesture() : nil)
                .onPreferenceChange(FramePreferenceKey<OverviewCard>.self) { dragFrames = $0 }
            }

            if windowState.isEditMode {
                editToolbar
            }
        }
        .onDisappear {
            // 离开概览页时退出编辑模式，窗口恢复可拖动
            windowState.isEditMode = false
        }
    }

    /// 把可见卡片分成行：宽卡独占一行，窄卡两两并排；落单窄卡补等宽占位。
    private var cardRows: [[OverviewCard]] {
        let list = visibleCards
        var rows: [[OverviewCard]] = []
        var i = 0
        while i < list.count {
            let card = list[i]
            if card.isWide {
                rows.append([card])
                i += 1
            } else if i + 1 < list.count, !list[i + 1].isWide {
                rows.append([card, list[i + 1]])
                i += 2
            } else {
                rows.append([card])
                i += 1
            }
        }
        return rows
    }

    // MARK: - 编辑模式（iOS 小组件式）下的增删与工具栏

    private var hiddenCards: [OverviewCard] { cards.filter { hidden.contains($0) } }

    private var emptyHint: some View {
        Text("还没有显示任何卡片 —— 进编辑模式，用底部「+ 添加小部件」把它们加回来。")
            .font(.system(size: 12))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 200)
    }

    /// 一张卡片在编辑模式下的「槽位」：accent 描边 + 右上角移除角标 + 可拖拽。
    /// 非编辑模式就是普通卡片（无描边、无角标、不可拖）。
    @ViewBuilder
    private func cardSlot(_ card: OverviewCard) -> some View {
        cardView(card)
            // 宽度只由行内布局决定：宽卡独占整行、窄卡固定占半行（落单也补占位），
            // 因此一张卡的大小与它被拖到哪个位置无关，拖拽前后尺寸一致。
            .frame(maxWidth: .infinity)
            .scaleEffect(draggingCard == card ? 1.05 : 1)
            .shadow(color: draggingCard == card ? Color.black.opacity(0.28) : Color.clear,
                    radius: draggingCard == card ? 12 : 0, y: draggingCard == card ? 4 : 0)
            .zIndex(draggingCard == card ? 100 : 0)
            .opacity(draggingCard == card ? 0.95 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(windowState.isEditMode ? Palette.accent.opacity(0.6) : Color.clear,
                            lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if windowState.isEditMode {
                    removeBadge(card)
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.8), value: draggingCard)
            .collectFrameIfEditing(windowState.isEditMode, id: card)
    }

    /// 编辑模式下每张卡右上角的「移除」角标（minus 圆标）。
    private func removeBadge(_ card: OverviewCard) -> some View {
        Button {
            removeCard(card)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Palette.accent)
        }
        .buttonStyle(.plain)
        .offset(x: 8, y: -8)
        .help("移除该卡片")
    }

    /// 编辑模式底部的工具栏：左侧「+ 添加小部件」（弹菜单列出被隐藏的卡），右侧「恢复默认」。
    private var editToolbar: some View {
        HStack(spacing: 10) {
            if hiddenCards.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("已全部添加")
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.faintFill))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Palette.hairline, lineWidth: 0.8))
            } else {
                Menu {
                    ForEach(hiddenCards) { card in
                        Button {
                            addCard(card)
                        } label: {
                            Label(card.title, systemImage: card.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加小部件")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.faintFill))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Palette.hairline, lineWidth: 0.8))
                }
                .menuStyle(.borderlessButton)
            }

            Spacer()

            Button("恢复默认") {
                restoreDefaults()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
        }
    }

    private func removeCard(_ card: OverviewCard) {
        hidden.insert(card)
        OverviewLayoutPrefs.setHidden(hidden)
    }

    private func addCard(_ card: OverviewCard) {
        hidden.remove(card)
        OverviewLayoutPrefs.setHidden(hidden)
    }

    private func restoreDefaults() {
        cards = OverviewCard.allCases
        hidden = []
        OverviewLayoutPrefs.setOrder(cards)
        OverviewLayoutPrefs.setHidden(hidden)
    }

    // MARK: - 长按拖拽排序

    /// 跟手拖拽排序（仅在编辑模式下挂载，见 body 的 .gesture 条件）：
    /// 拖的过程中实时重排——手指移到另一张卡片的槽位上时，立即把被拖卡片插到它旁边，
    /// 其它卡片用弹簧动画让位，整个过程连续顺滑，不再等松手才「啪」地跳一下。
    /// 窗口背景拖动由 WindowState.isEditMode 联动关掉，所以拖卡片时窗口绝不会被带跑。
    /// 挂在卡片网格容器上：抬起的视觉效果交给 @GestureState，无论手势正常结束还是被取消都会自动缩回。
    private func gridDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($draggingCard) { value, state, _ in
                // 只在抓起的一瞬确定动的是哪张卡：之后卡片会互相让位，
                // 再按起点坐标去重算会认到让位后的那张卡上。
                if state == nil {
                    state = cardUnder(value.startLocation)
                }
            }
            .onChanged { value in
                if dragSource == nil { dragSource = cardUnder(value.startLocation) }
                guard let card = dragSource,
                      let target = cardUnder(value.location), target != card else { return }
                reorderLive(card, to: target)
            }
            .onEnded { _ in
                // 松开后 @GestureState 自己复位；这里只收尾 + 持久化顺序。
                dragSource = nil
                OverviewLayoutPrefs.setOrder(cards)
            }
    }

    /// 命中测试：返回某点下方的卡片（拖拽排序与角标移除的判断都用全局坐标）
    private func cardUnder(_ point: CGPoint) -> OverviewCard? {
        dragFrames.first(where: { $0.value.contains(point) })?.key
    }

    /// 实时重排（不落盘，松手才持久化）：把 card 移动到 target 旁边。
    /// 往下拖插到目标后面，往上拖插到目标前面。外部已用弹簧 withAnimation 包住，卡片让位更顺。
    private func reorderLive(_ card: OverviewCard, to target: OverviewCard) {
        guard let from = cards.firstIndex(of: card),
              let to = cards.firstIndex(of: target), from != to else { return }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
            cards.remove(at: from)
            if from < to {
                if let idx = cards.firstIndex(of: target) { cards.insert(card, at: idx + 1) }
                else { cards.append(card) }
            } else {
                if let idx = cards.firstIndex(of: target) { cards.insert(card, at: idx) }
                else { cards.insert(card, at: 0) }
            }
        }
        // 每次实时重排都立刻落盘，而不是只等松手（onEnded）——
        // 拖拽若被中断（切页、手势取消等）导致 onEnded 没触发，顺序也不会丢，重启即还原。
        OverviewLayoutPrefs.setOrder(cards)
    }

    @ViewBuilder
    private func cardView(_ card: OverviewCard) -> some View {
        switch card {
        case .cpuTemp:    cpuCard
        case .gpu:        gpuCard
        case .fan:        fanCard
        case .battery:    batteryCard
        case .disk:       diskCard
        case .mode:       ModeStatusCard()
        case .load:       LoadCard()
        case .capability: capabilitySummary
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "设备概览", subtitle: deviceSummary)
            HStack(spacing: 8) {
                Button { PageRouter.shared.jump(to: .performance) } label: {
                    Label("性能与风扇", systemImage: "speedometer")
                }
                .buttonStyle(GrayButtonStyle(prominent: true))

                Button { PageRouter.shared.jump(to: .keyboard) } label: {
                    Label("键盘灯效", systemImage: "keyboard")
                }
                .buttonStyle(GrayButtonStyle())

                Spacer(minLength: 8)

                Button {
                    windowState.isEditMode.toggle()
                } label: {
                    Label(windowState.isEditMode ? "完成" : "编辑布局",
                          systemImage: windowState.isEditMode ? "checkmark" : "square.grid.2x2")
                }
                .buttonStyle(GrayButtonStyle())
            }
        }
    }

    private var deviceSummary: String {
        let name = store.hardware.productName.isEmpty ? store.hardware.modelName : store.hardware.productName
        let code = store.hardware.modelCode
        let device = name.isEmpty ? (code.isEmpty ? "当前设备" : code) : name
        return "\(device) · \(store.hardware.cpuShort) · \(String(format: "%.0f", store.hardware.ramGB)) GB 内存"
    }

    private var cpuCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "CPU", trailing: "处理器")
                HStack(spacing: 16) {
                    TempRing(value: store.cpuTemp, size: 92)
                        .help(store.menuValue(.cpuTemp).reason ?? "CPU 温度")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            statusIndicator(store.tempStatusText, color: Palette.forTemp(store.cpuTemp))
                            Spacer(minLength: 4)
                            Text(String(format: "%.0f%% 负载", store.load.total * 100))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Text("最低 \(temperatureText(tempMin)) · 最高 \(temperatureText(tempMax))")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("热压力 · \(store.load.thermalText)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(store.load.thermal == .nominal ? Palette.textSecondary : Palette.warn)
                        Sparkline(values: store.loadHistory.map { $0 * 100 }, color: Palette.mLoad,
                                  lowerBound: 0, upperBound: 100, filled: false)
                            .frame(height: 22)
                            .accessibilityLabel("CPU 负载趋势")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 92)

                Rectangle().fill(Palette.hairline).frame(height: 1)

                HStack(spacing: 20) {
                    metricTrend("平均频率",
                                value: store.cpuFreq.liveGHz.map { String(format: "%.2f", $0) } ?? "—",
                                unit: "GHz", has: store.cpuFreq.liveGHz != nil,
                                color: Palette.mFreq, values: store.freqHistory, upper: 5.5)
                        .help(store.menuValue(.cpuFreq).reason ?? store.cpuFrequencyDetail)
                    metricTrend("功耗",
                                value: store.powerWatts.map { String(format: "%.1f", $0) } ?? "—",
                                unit: "W", has: store.powerWatts != nil,
                                color: Palette.mPower, values: store.powerHistory, upper: 100)
                        .help(store.menuValue(.power).reason ?? "CPU 整包功耗")
                }

                Text(store.cpuFrequencyDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .help(store.menuValue(.cpuFreq).reason ?? store.cpuFrequencyDetail)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 264)
    }

    private var tempMin: Double? { store.tempHistory.min() ?? store.cpuTemp }
    private var tempMax: Double? { store.tempHistory.max() ?? store.cpuTemp }

    private func temperatureText(_ value: Double?) -> String {
        value.map { String(format: "%.0f °C", $0) } ?? "—"
    }

    private func statusIndicator(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
        }
    }

    private var fanCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "风扇", trailing: store.fanAvailable ? "实时转速" : "不可用")
                HStack(spacing: 12) {
                    fanMetric("CPU", store.fanRPM)
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 32)
                    fanMetric("GPU", store.fanRPMGPU)
                    if let center = store.fanRPMCenter {
                        Rectangle().fill(Palette.hairline).frame(width: 1, height: 32)
                        fanMetric("中置", center)
                    }
                }
                Text(store.fanAvailable ? store.fanSource : "未收到转速反馈")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .help(store.fanAvailable ? store.fanSource : store.fanUnavailableReason)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: smallCardHeight)
    }

    private func fanMetric(_ label: String, _ rpm: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(store.fanAvailable ? (rpm.map { String(format: "%.0f", $0) } ?? "—") : "—")
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(store.fanAvailable ? Palette.text : Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("RPM").font(.system(size: 9)).foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var batteryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "电池", trailing: store.battery.externalPower ? "已连接电源" : "电池供电")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(store.battery.charge)")
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    Text("%").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Image(systemName: store.battery.externalPower ? "powerplug.fill" : "battery.50")
                        .font(.system(size: 14))
                        .foregroundStyle(store.battery.externalPower ? Palette.ok : Palette.textSecondary)
                }
                BatteryBar(percent: store.battery.charge)
                Text("健康 \(String(format: "%.0f%%", store.battery.healthPercent)) · \(store.battery.cycleCount) 次循环")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: smallCardHeight)
    }

    private var diskCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "磁盘", trailing: store.disk.volumeName.isEmpty ? "启动宗卷" : store.disk.volumeName)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", store.disk.usedFraction * 100))
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.forDisk(store.disk.usedFraction))
                    Text("%").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 4)
                    Text("可用 \(ByteCountFormatter.vela.string(fromByteCount: store.disk.availableBytes))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.trackFill)
                        Capsule().fill(Palette.forDisk(store.disk.usedFraction))
                            .frame(width: max(geo.size.width * CGFloat(min(max(store.disk.usedFraction, 0), 1)), 2))
                    }
                }
                .frame(height: 5)
                Text("已用 \(ByteCountFormatter.vela.string(fromByteCount: store.disk.usedBytes)) / 共 \(ByteCountFormatter.vela.string(fromByteCount: store.disk.totalBytes))")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: smallCardHeight)
    }

    private var gpuCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "GPU", trailing: "显卡")
                    .help(store.gpuName ?? "等待 GPU 识别…")
                HStack(spacing: 16) {
                    TempRing(value: store.gpuTemp, size: 92)
                        .help(store.menuValue(.gpuTemp).reason ?? "GPU 温度")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            statusIndicator(gpuTempStatusText, color: Palette.forTemp(store.gpuTemp))
                            Spacer(minLength: 4)
                            Text(store.gpuUsage.map { String(format: "%.0f%% 负载", $0) } ?? "—")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.textSecondary)
                                .help(store.menuValue(.gpuLoad).reason ?? "GPU 占用率")
                        }
                        Text("核心频率 \(store.gpuFrequencyMHz.map { String(format: "%.0f MHz", $0) } ?? "—")")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(Palette.textSecondary)
                            .help(store.menuValue(.gpuFreq).reason ?? "GPU 核心频率")
                        Text("占用率趋势")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textTertiary)
                        Sparkline(values: store.gpuHistory, color: Palette.mGPU,
                                  lowerBound: 0, upperBound: 100, filled: false)
                            .frame(height: 22)
                            .accessibilityLabel("GPU 占用率趋势")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 92)

                Rectangle().fill(Palette.hairline).frame(height: 1)

                HStack(spacing: 20) {
                    metricTrend("功耗",
                                value: store.gpuPowerWatts.map { String(format: "%.1f", $0) } ?? "—",
                                unit: "W", has: store.gpuPowerWatts != nil,
                                color: Palette.mGPUPow, values: store.gpuPowerHistory,
                                upper: max(30, store.gpuPowerLimitWatts ?? 120))
                        .help(store.menuValue(.gpuPower).reason ?? "GPU 功耗")
                    metricTrend("显存",
                                value: store.vramUsedMB.map { String(format: "%.1f", $0 / 1024) } ?? "—",
                                unit: "GiB", has: store.vramUsedMB != nil,
                                color: Palette.mVRAM, values: store.vramHistory,
                                upper: max(1, store.vramTotalMB ?? 1))
                        .help(store.menuValue(.gpuVRAM).reason ?? vramShortText)
                }

                Text(vramShortText)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .help(store.menuValue(.gpuVRAM).reason ?? vramShortText)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 264)
    }

    private func metricTrend(_ title: String, value: String, unit: String,
                             has: Bool, color: Color, values: [Double], upper: Double) -> some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10.5)).foregroundStyle(Palette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .foregroundStyle(has ? Palette.text : Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(unit).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Sparkline(values: values, color: color, lowerBound: 0, upperBound: upper, filled: false)
                .frame(width: 40, height: 28)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gpuTempStatusText: String {
        guard let t = store.gpuTemp else { return "无数据" }
        switch t {
        case ..<55: return "凉爽"
        case ..<70: return "正常"
        case ..<85: return "偏高"
        case ..<95: return "高温"
        default: return "过热"
        }
    }

    private var vramShortText: String {
        if let used = store.vramUsedMB, let total = store.vramTotalMB {
            return String(format: "%.0f MiB / %.1f GiB", used, total / 1024)
        }
        if let used = store.vramUsedMB { return String(format: "已用 %.0f MiB", used) }
        if let total = store.vramTotalMB { return String(format: "容量 %.1f GiB；未提供已用显存", total / 1024) }
        return "未提供显存读数"
    }

    private var capabilitySummary: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: "设备能力", trailing: "macOS 支持状态")
                    Button {
                        PageRouter.shared.jump(to: .diagnostics)
                    } label: {
                        Label("查看诊断", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(GrayButtonStyle())
                }
                ForEach(store.capabilities.prefix(5)) { cap in
                    CapabilityRow(cap: cap)
                }
            }
        }
    }
}


