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

    /// 窄卡（功耗/频率/显卡/风扇/电池）统一高度，保证两两并排时对齐
    private let smallCardHeight: CGFloat = 108

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

    /// 把可见卡片分成行：宽卡独占一行，窄卡两两并排；落单窄卡占满整行（避免左右不对称）
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
                RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                    .stroke(windowState.isEditMode ? Palette.accent.opacity(0.6) : Color.clear,
                            lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if windowState.isEditMode {
                    removeBadge(card)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if Palette.isTianxuan, let idx = visibleCards.firstIndex(of: card) {
                    Text(String(format: "%02d", idx + 1))
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.accent.opacity(0.30))
                        .padding(.trailing, 11)
                        .padding(.bottom, 7)
                        .allowsHitTesting(false)
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

    @ViewBuilder
    private var header: some View {
        Card(padding: 20, accent: Palette.accent) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("TIANXUAN / 03").font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.8).foregroundStyle(Palette.accent)
                        Spacer(minLength: 0)
                    }
                    Text("天选 3 · 控制中心").font(.system(size: 27, weight: .black))
                        .foregroundStyle(Palette.text)
                    Text(deviceSummary).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Button { PageRouter.shared.jump(to: .performance) } label: {
                            Label("性能与风扇", systemImage: "speedometer")
                        }.buttonStyle(GrayButtonStyle(prominent: true))
                        Button { PageRouter.shared.jump(to: .keyboard) } label: {
                            Label("键盘灯效", systemImage: "keyboard")
                        }.buttonStyle(GrayButtonStyle())
                        Spacer(minLength: 0)
                        Button(windowState.isEditMode ? "完成" : "编辑布局") {
                            windowState.isEditMode.toggle()
                        }.buttonStyle(GrayButtonStyle())
                    }
                }
                TianxuanEmblem(height: 94).opacity(0.22).accessibilityHidden(true)
            }
        }
    }
    private var deviceSummary: String {
        let name = store.hardware.productName.isEmpty ? store.hardware.modelName : store.hardware.productName
        let code = store.hardware.modelCode
        let device = name.isEmpty ? (code.isEmpty ? "当前设备" : code) : name
        return "当前设备：\(device) · \(store.hardware.cpuShort) · \(String(format: "%.0f", store.hardware.ramGB)) GB RAM"
    }

    private var cpuCard: some View {
        // CPU 合并卡：左侧温度环 + 状态四行，右侧负载曲线；底部「频率 / 功耗」左右并排、各带一条波形。
        // 压缩思路：环 116→96、曲线 84/58→68/46、字号 19→17，
        // 并把原本上下两行的频率与功耗改成左右各半 —— 宽卡横向本来就有余量，
        // 竖着堆两整行纯属浪费，卡片高度因此少了约三分之一。
        Card(padding: 16, glow: true) {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "CPU", trailing: "温度 · 频率 · 功耗", color: Palette.mLoad, code: "SYS.CPU", command: "cpu --stat")
                Spacer(minLength: 6)
                HStack(alignment: .center, spacing: 16) {
                    if Palette.isTianxuan {
                        TianxuanTempShadow(value: store.cpuTemp, size: 96)
                    } else {
                        TempRing(value: store.cpuTemp, size: 96)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        statLine("状态", store.tempStatusText,
                                 color: Palette.forTemp(store.cpuTemp))
                        statLine("最低", String(format: "%.1f °C", tempMin))
                        statLine("最高", String(format: "%.1f °C", tempMax))
                        statLine("热压力", store.load.thermalText,
                                 color: store.load.thermal == .nominal ? Palette.ok : Palette.warn)
                    }
                    // 固定宽度：让 CPU 卡与 GPU 卡的曲线起点落在同一条竖线上
                    .frame(width: 146, alignment: .leading)
                    // 右侧空白用 CPU 负载曲线填充（Sparkline 无网格 / 表格背景）
                    VStack(alignment: .leading, spacing: 4) {
                        CodeLabel(text: "负载曲线", size: 9.5)
                        Sparkline(values: store.loadHistory.map { $0 * 100 },
                                  color: Palette.mLoad,
                                  lowerBound: 0, upperBound: 100,
                                  filled: false, axes: true)
                            .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 68)
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 8)
                // 频率 / 功耗并排
                HStack(alignment: .center, spacing: 20) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                        metricCell("平均频率",
                                   value: store.cpuFreq.liveGHz.map { String(format: "%.2f", $0) } ?? "—",
                                   unit: "GHz",
                                   has: store.cpuFreq.liveGHz != nil,
                                   color: Palette.mFreq)
                        Text(store.cpuFrequencyDetail)
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textSecondary)
                        }
                        FreqECG(values: store.freqHistory,
                                color: Palette.mFreq,
                                lower: 0, upper: 5.5, height: 46, axes: true)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)

                    // 功耗：大数 + 折线图（表征 CPU 整包功耗随时间起伏）
                    HStack(alignment: .center, spacing: 10) {
                        metricCell("功耗",
                                   value: store.powerWatts.map { String(format: "%.1f", $0) } ?? "—",
                                   unit: "W",
                                   has: store.powerWatts != nil,
                                   color: Palette.mPower)
                        Sparkline(values: store.powerHistory,
                                  color: Palette.mPower,
                                  lowerBound: 0, upperBound: 100,
                                  filled: true, axes: true)
                            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var tempMin: Double { store.tempHistory.min() ?? store.cpuTemp ?? 0 }
    private var tempMax: Double { store.tempHistory.max() ?? store.cpuTemp ?? 0 }

    private func statLine(_ label: String, _ value: String,
                          color: Color = Palette.text) -> some View {
        HStack(spacing: 5) {
            CodeLabel(text: label, size: 9.5)
                .frame(width: 40, alignment: .leading)
            if Palette.isTianxuan {
                // 规格表式引导规：虚线吃掉中间的空隙，值被推到右端。
                // 用弹性 Shape 而不是固定长度的「·」，否则窄列里会被压成 0 宽（踩过）。
                DashedRule()
                    .stroke(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 3)
            }
            Text(Palette.isTianxuan ? TianxuanText.code(value) : value)
                .font(Palette.isTianxuan ? TianxuanFont.number(12) : .system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
        }
    }

    private var fanCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "风扇", trailing: store.fanAvailable ? "实时" : "不可用",
                             color: Palette.mFan, code: "COOLANT", command: "coolant --status")
                // 左右各占一半、中间细分隔线，两列对称
                // CPU 风扇用风扇色（青绿），GPU 风扇跟随显卡的身份色（紫），一眼看出属谁
                if Palette.isTianxuan {
                    VStack(alignment: .leading, spacing: 5) {
                        fanStatusRow("CPU 风扇", store.fanRPM, Palette.mFan)
                        fanStatusRow("GPU 风扇", store.fanRPMGPU, Palette.mGPU).padding(.top, 1)
                        if let center = store.fanRPMCenter {
                            fanStatusRow("中置风扇", center, Palette.mFan)
                        }
                    }
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 0) {
                        fanMetric("CPU", store.fanRPM, color: Palette.mFan)
                            .frame(maxWidth: .infinity)
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(width: 1, height: 36)
                        fanMetric("GPU", store.fanRPMGPU, color: Palette.mGPU)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 2)
                }
                Text(store.fanAvailable ? store.fanSource : "未收到转速反馈")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .help(store.fanAvailable ? store.fanSource : store.fanUnavailableReason)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: smallCardHeight)
    }


    private func fanStatusRow(_ key: String, _ rpm: Double?, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.accent.opacity(0.8))
            Text(String(repeating: "·", count: 12))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.hairline)
                .lineLimit(1)
                .layoutPriority(-1)
            Spacer(minLength: 0)
            Text(store.fanAvailable ? (rpm.map { String(format: "%.0f", $0) } ?? "—") : "—")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(store.fanAvailable ? color : Palette.textSecondary)
            Text("RPM")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    /// 风扇卡里的一列：小标题 CPU/GPU + 转速大字
    private func fanMetric(_ label: String, _ rpm: Double?, color: Color) -> some View {
        VStack(spacing: 2) {
            if Palette.isTianxuan {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Palette.accent.opacity(0.8))
            } else {
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(store.fanAvailable ? (rpm.map { String(format: "%.0f", $0) } ?? "—") : "—")
                    .font(Palette.isTianxuan
                          ? .system(size: 21, weight: .semibold, design: .monospaced)
                          : .system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(store.fanAvailable ? color : Palette.textSecondary)
                Text("RPM")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var batteryCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "电池", color: Palette.mBattery, code: "PWR.CELL", command: "power --cell")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(store.battery.charge)")
                        .font(.system(size: 25, weight: .semibold).monospacedDigit())
                    Text("%")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Image(systemName: store.battery.externalPower ? "powerplug.fill" : "battery.50")
                        .font(.system(size: 11))
                        .foregroundStyle(store.battery.externalPower ? Palette.ok : .secondary)
                }
                BatteryBar(percent: store.battery.charge)
                if Palette.isTianxuan {
                    Text("健康 \(String(format: "%.0f%%", store.battery.healthPercent)) · \(store.battery.cycleCount) 次循环")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    Text("健康 \(String(format: "%.0f%%", store.battery.healthPercent)) · \(store.battery.cycleCount) 次循环")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: smallCardHeight)
    }

    private var diskCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "磁盘", trailing: store.disk.volumeName.isEmpty ? "启动宗卷" : store.disk.volumeName,
                             color: Palette.mDisk, code: "STORAGE", command: "storage --usage")
                // 占用率大字 + 剩余
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", store.disk.usedFraction * 100))
                        .font(.system(size: 25, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.forDisk(store.disk.usedFraction))
                    Text("%")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    if Palette.isTianxuan {
                        CodeRow(key: "可用",
                                value: ByteCountFormatter.vela.string(fromByteCount: store.disk.availableBytes),
                                size: 10, valueColor: Palette.textSecondary)
                    } else {
                        Text("可用 \(ByteCountFormatter.vela.string(fromByteCount: store.disk.availableBytes))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                // 占用率条
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.trackFill).frame(height: 6)
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.forDisk(store.disk.usedFraction),
                                                         Palette.forDisk(store.disk.usedFraction).opacity(0.7)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(w * CGFloat(store.disk.usedFraction), 2), height: 6)
                    }
                }
                .frame(height: 6)
                if Palette.isTianxuan {
                    CodeRow(key: "已用",
                            value: "\(ByteCountFormatter.vela.string(fromByteCount: store.disk.usedBytes)) / \(ByteCountFormatter.vela.string(fromByteCount: store.disk.totalBytes))",
                            size: 10, valueColor: Palette.textSecondary)
                } else {
                    Text("已用 \(ByteCountFormatter.vela.string(fromByteCount: store.disk.usedBytes)) / 共 \(ByteCountFormatter.vela.string(fromByteCount: store.disk.totalBytes))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: smallCardHeight)
    }

    private var gpuCard: some View {
        // 显卡合并卡：与 CPU 卡完全同构 —— 温度环 + 状态/占用率/功耗/显存四行 + 占用率曲线，
        // 底部「功耗 / 显存」左右并排、各带面积折线（与 CPU 卡的频率/功耗行同尺寸）。
        // 功耗与显存原先是两张独立的窄卡，按「温度 · 功耗 · 显存」并到这里。
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "GPU", trailing: "温度 · 频率 · 功耗 · 显存", color: Palette.mGPU, code: "SYS.GPU", command: "gpu --stat")
                    .help(store.gpuName ?? "等待 GPU 识别…")
                Spacer(minLength: 6)
                HStack(alignment: .center, spacing: 16) {
                    if Palette.isTianxuan {
                        TianxuanTempShadow(value: store.gpuTemp, size: 96)
                    } else {
                        TempRing(value: store.gpuTemp, size: 96)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        statLine("状态", gpuTempStatusText,
                                 color: Palette.forTemp(store.gpuTemp))
                        statLine("占用率", store.gpuUsage.map { String(format: "%.0f %%", $0) } ?? "—",
                                 color: Palette.mGPU)
                        statLine("核心频率", store.gpuFrequencyMHz.map { String(format: "%.0f MHz", $0) } ?? "—",
                                 color: Palette.mFreq)
                            .help(store.menuValue(.gpuFreq).reason ?? "GPU 核心频率")
                        // 功耗与显存不再在这里列一遍 —— 底部有大数 + 曲线，重复显示只会让卡更挤
                    }
                    .frame(width: 146, alignment: .leading)
                    // 右侧用显卡占用率曲线填充（与 CPU 卡的负载曲线同一位置）
                    VStack(alignment: .leading, spacing: 4) {
                        CodeLabel(text: "占用率曲线", size: 9.5)
                        Sparkline(values: store.gpuHistory,
                                  color: Palette.mGPU,
                                  lowerBound: 0, upperBound: 100,
                                  filled: false, axes: true)
                            .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 68)
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 8)
                // 功耗 / 显存并排（上限取自驱动上报的强制功耗墙 / 显存总量）
                HStack(alignment: .center, spacing: 20) {
                    HStack(alignment: .center, spacing: 10) {
                        metricCell("功耗",
                                   value: store.gpuPowerWatts.map { String(format: "%.1f", $0) } ?? "—",
                                   unit: "W",
                                   has: store.gpuPowerWatts != nil,
                                   color: Palette.mGPUPow)
                            .help(store.menuValue(.gpuPower).reason ?? "GPU 功耗")
                        Sparkline(values: store.gpuPowerHistory,
                                  color: Palette.mGPUPow,
                                  lowerBound: 0,
                                  upperBound: max(30, store.gpuPowerLimitWatts ?? 120),
                                  filled: true, axes: true)
                            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
                    }
                    .frame(maxWidth: .infinity)

                    HStack(alignment: .center, spacing: 10) {
                        metricCell("显存",
                                   value: store.vramUsedMB.map { String(format: "%.1f", $0 / 1024) } ?? "—",
                                   unit: "GiB",
                                   has: store.vramUsedMB != nil,
                                   color: Palette.mVRAM)
                            .help(store.menuValue(.gpuVRAM).reason ?? vramShortText)
                        Sparkline(values: store.vramHistory,
                                  color: Palette.mVRAM,
                                  lowerBound: 0,
                                  upperBound: max(1, store.vramTotalMB ?? 1),
                                  filled: true, axes: true)
                            .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// 宽卡底部「小标题 + 大数 + 单位」那一小格（CPU 的频率/功耗、GPU 的功耗/显存共用）。
    /// 1.8.10 起两格并排，宽度收窄到 62、字号 19→17，横向留给波形。
    private func metricCell(_ title: String, value: String, unit: String,
                            has: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CodeLabel(text: title, size: 9.5)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Palette.isTianxuan ? TianxuanFont.number(19)
                                         : .system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(has ? color : Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(unit)
                    .font(Palette.isTianxuan ? .system(size: 9, weight: .semibold, design: .monospaced)
                                         : .system(size: 9.5))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(width: 62, alignment: .leading)
    }

    /// 与 CPU 的状态文案同一套阈值，只换数据源
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
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(text: "macOS 上的能力边界", trailing: "详见「诊断」", color: Palette.accent, code: "SYSINFO", command: "sysinfo --limits")
                ForEach(store.capabilities.prefix(5)) { cap in
                    CapabilityRow(cap: cap)
                }
            }
        }
    }
}


