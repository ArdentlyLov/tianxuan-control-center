// PerformanceView.swift

import SwiftUI
import AppKit
import Combine

// MARK: - 性能与风扇

struct PerformanceView: View {
    @EnvironmentObject var store: SensorStore
    /// 风扇档位状态（kext 状态、双风扇转速、下发进度、机型选择）
    @StateObject private var fan = FanControl.shared
    /// 手动输入机型代码的临时文本
    @State private var manualModel = ""
    /// 手动输入机型代码区：默认收起，点「机型不匹配？」才展开
    @State private var showManualModel = false
    /// 是否展开「判定依据」（各候选机型的得分与命中项）
    @State private var showEvidence = false
    /// 免责声明弹窗的当前任务（nil = 不显示）。preset 为要应用的档位，nil 表示仅确认
    @State private var disclaimerItem: DisclaimerItem?

    /// 免责弹窗要确认的任务
    private struct DisclaimerItem: Identifiable {
        let id = UUID()
        /// 确认后要应用的档位名；nil 表示只是「查看风险并继续」的确认
        let preset: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "性能与风扇", subtitle: "调整性能模式、功耗上限与散热策略。")
            FirmwareControlCard()
            // [VelaX-PowerLimit] 功耗墙档位（真实可用的「性能模式」：静音/平衡/性能 + 自定义）
            PowerLimitCard()

            SectionTitle(text: "风扇曲线",
                         trailing: fan.kextLoaded ? (fan.kextBuild ?? "kext 已加载") : "kext 未加载", command: "coolant --curve")

            Card {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .center, spacing: 20) {
                        fanStat("CPU 风扇", store.fanRPM.map { String(Int($0)) } ?? "—")
                        fanStat("GPU 风扇", store.fanRPMGPU.map { String(Int($0)) } ?? "—")
                        if let center = store.fanRPMCenter {
                            fanStat("中置风扇", String(Int(center)))
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("当前档位")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.textTertiary)
                            Text(currentPresetLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(fan.activePreset == nil ? Palette.textSecondary : Palette.accent)
                        }
                    }

                    Text(store.fanAvailable ? "转速来源：\(store.fanSource)" : store.fanUnavailableReason)
                        .font(.system(size: 10.5))
                        .foregroundStyle(store.fanAvailable ? Palette.textTertiary : Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)

                    if !fan.kextLoaded {
                        Text("风扇曲线写入接口未连接。转速反馈会独立检查华硕 WMI 和 SMC 通道。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let presets = fan.presets {
                        VStack(spacing: 6) {
                            ForEach(FanControl.order, id: \.self) { name in
                                if let preset = presets.preset(name) {
                                    presetRow(name: name, preset: preset)
                                }
                            }
                        }
                    } else if let err = fan.loadError {
                        Text("读不到风扇曲线配置：\(err)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let message = fan.message {
                        Text(message)
                            .font(.system(size: 10.5))
                            .foregroundStyle(message.hasPrefix("已切到") || message.hasPrefix("已下发") ? Palette.ok : Palette.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // MARK: 机型识别
            // 不同机型 EC 配置不同：先认出真实机型，机主可手动选（按型号名），
            // 所选机型与检测到的硬件不一致时，应用曲线前必须确认硬件损坏风险。
            Card {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 10) {
                        Text("机型")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 6)
                        // 匹配状态指示（三态：匹配 / 没能自动识别 / 不匹配）
                        HStack(spacing: 4) {
                            Circle().fill(modelStatusColor(fan.status))
                                .frame(width: 6, height: 6)
                            Text(modelStatusLabel(fan.status))
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(modelStatusColor(fan.status))
                        }
                        // 快速选择菜单（判定出的机型 + 已收录机型族）
                        Menu {
                            if fan.detection.confidence != .none {
                                Button {
                                    fan.selectModel(fan.detection.code)
                                } label: {
                                    Label("使用判定的机型 \(fan.detection.code)（推荐）",
                                          systemImage: "checkmark.circle")
                                }
                                Divider()
                            }
                            ForEach(ECProfiles.catalog, id: \.id) { p in
                                Button {
                                    fan.selectModel(p.modelCodes.first ?? p.familyName)
                                } label: {
                                    Text("\(p.familyName)  ·  \(p.modelCodes.first ?? "")")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(fan.selectedCode.isEmpty ? "选择机型" : fan.selectedCode)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 9))
                            }
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Palette.accent.opacity(0.16)))
                            .foregroundStyle(Palette.accent)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // 判定出的机型 + 置信度
                    HStack(spacing: 4) {
                        Text(fan.detection.confidence == .none ? "未能识别" : "推断")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                        Text(fan.detection.confidence == .none
                             ? "本机硬件指纹不匹配任何已收录机型"
                             : "\(fan.detection.code)（\(fan.detection.name)）")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        if fan.detection.confidence != .none {
                            Text("· \(fan.detection.confidence.label)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }

                    // 硬件指纹（判定依据的原始数据）
                    if !fan.detection.evidenceLine.isEmpty {
                        Text(fan.detection.evidenceLine)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // 电池部件号：明确说明它不作数，免得机主以为「程序认错机型了」
                    if let part = fan.detection.fingerprint.batteryName {
                        Text("电池部件号 \(part)：多机型共用，不作判定依据")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.textTertiary)
                    }

                    // 展开每个候选机型的命中项
                    Button {
                        showEvidence.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text(showEvidence ? "收起判定依据" : "查看判定依据")
                                .font(.system(size: 9.5, weight: .medium))
                            Image(systemName: showEvidence ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundStyle(Palette.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showEvidence {
                        VStack(alignment: .leading, spacing: 5) {
                            if fan.detection.scores.isEmpty {
                                Text("没有任何已收录机型命中本机硬件。请对照机身底部或包装箱上的型号手动选择。")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Palette.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(fan.detection.scores, id: \.profile.id) { s in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(s.profile.modelCodes.first ?? s.profile.familyName) · \(s.points) 分")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(Palette.textSecondary)
                                        ForEach(s.reasons, id: \.self) { r in
                                            Text("· \(r)")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(Palette.textTertiary)
                                        }
                                    }
                                }
                            }
                            Text("推断以独显型号为主（同 CPU 的枪神/魔霸靠独显档位区分），CPU 只看世代；不看 SMBIOS（黑苹果下已换成 Mac），也不看电池部件号。")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 2)
                    }

                    // 手动输入机型：默认收起，用「机型不匹配？」作为开关
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showManualModel.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Text("机型不匹配？")
                                .font(.system(size: 9.5, weight: .medium))
                            Image(systemName: showManualModel ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundStyle(Palette.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showManualModel {
                    HStack(spacing: 8) {
                        TextField("输入机型代码，如 G513RM", text: $manualModel)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.panelTop.opacity(0.5))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Palette.cardStroke, lineWidth: 0.6)))
                        Button {
                            fan.selectModel(manualModel)
                            manualModel = ""
                        } label: {
                            Text("应用此机型")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .disabled(manualModel.trimmingCharacters(in: .whitespaces).isEmpty)
                        .foregroundStyle(Palette.accent)
                    }
                    }

                    // 已收录机型的 EC 配置摘要
                    if !ASUSWMIBridge.shared.isAvailable, let p = fan.ecProfile {
                        HStack(spacing: 4) {
                            Text("EC 配置")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textTertiary)
                            Text("\(p.ecChip) · \(p.ecFirmware)")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textSecondary)
                            Text("· \(p.verification.label)")
                                .font(.system(size: 10))
                                .foregroundStyle(p.verification == .verifiedOnDevice
                                                 ? Palette.ok : Palette.warn)
                            if fan.ecLevel == .compatible {
                                Text("（家族兼容，未本机验证）")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Palette.warn)
                            }
                        }

                        // 逆向未实机验证的机型：把「先做只读验证」讲清楚，
                        // 别让人误以为和实机验证过的机型一样可以放心直接下发
                        if let caveat = p.verification.caveat {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.warn)
                                Text(caveat)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }

            // 机型不匹配 → 硬件损坏风险警告（应用曲线前必须先确认）
            if fan.status == .mismatched {
                Card {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Palette.bad).font(.system(size: 14))
                            Text("机型不匹配：写入曲线可能损坏硬件")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.bad)
                        }
                        Text("你选择的「\(fan.selectedCode)」与本机判定出的「\(fan.detection.code)」不一致（判定依据：\(fan.detection.evidenceLine)）。风扇曲线和 EC 配置是按特定机型逆向的，套错机型可能让风扇停转或狂转，导致过热甚至永久损坏。每次应用曲线前都必须先确认风险。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !fan.acknowledgedMismatch {
                            Button {
                                // 打开免责声明弹窗（不立即应用，仅做确认）
                                disclaimerItem = DisclaimerItem(preset: nil)
                            } label: {
                                Text("查看风险并继续")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .padding(.horizontal, 11).padding(.vertical, 5)
                                    .background(Capsule().fill(Palette.bad.opacity(0.15)))
                                    .overlay(Capsule().stroke(Palette.bad.opacity(0.4), lineWidth: 0.8))
                                    .foregroundStyle(Palette.bad)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("已确认风险，可以继续应用曲线。")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.ok)
                        }
                    }
                }
            }

            // 没能自动识别机型 → 提示先核对型号（同样要求确认一次，因为无从核对）
            if fan.status == .undetected, !fan.acknowledgedMismatch {
                Card {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundStyle(Palette.warn).font(.system(size: 14))
                            Text("机型未能自动识别")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.warn)
                        }
                        Text("本机硬件指纹（\(fan.detection.evidenceLine)）没有匹配到任何已收录机型，无法核对你选的「\(fan.selectedCode)」。曲线和 EC 配置是按特定机型逆向的，机型不对可能损坏硬件：请对照机身底部或包装箱上的型号核对后，再点下面的按钮确认。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            disclaimerItem = DisclaimerItem(preset: nil)
                        } label: {
                            Text("核对并确认机型")
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .background(Capsule().fill(Palette.warn.opacity(0.15)))
                                .overlay(Capsule().stroke(Palette.warn.opacity(0.4), lineWidth: 0.8))
                                .foregroundStyle(Palette.warn)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // [VelaX-CustomCurve] 自定义曲线编辑器（未在「高级功能」解锁时不显示）
            CustomCurveGate()

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("这条通道是怎么打通的")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(ASUSWMIBridge.shared.isAvailable
                         ? "本机通过 ASUS 固件接口控制。原厂静音、平衡、增强档位会同时切换性能与风扇策略，应用后确认固件结果。转速每 0.5 秒读取一次。增强会按温度调速，并不代表风扇始终满速。CPU 频率仍由系统与固件根据负载、温度和功耗决定。"
                         : "本机通过 SMC 风扇接口控制。应用时提交所选曲线，转速每 0.5 秒读取一次；实际转速取决于温度和曲线设置。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2.5)
                }
            }
        }
        .onAppear { fan.refresh() }
        // 转速由 SensorStore 每半秒推送；这里仅复查驱动和曲线状态。
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            if fan.applying == nil { fan.refresh() }
        }
        // 机型不匹配的硬件损坏风险免责弹窗（由本地 @State 驱动，避免属性环）
        .sheet(item: $disclaimerItem) { item in
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.bad).font(.system(size: 22))
                    Text(fan.status == .mismatched
                         ? ModelDisclaimer.title
                         : ModelDisclaimer.titleUndetected)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    Text(fan.status == .mismatched
                         ? ModelDisclaimer.body(selected: fan.selectedCode,
                                                detected: fan.detection.code)
                         : ModelDisclaimer.bodyUndetected(selected: fan.selectedCode))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.text)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 230)
                HStack(spacing: 10) {
                    Button {
                        disclaimerItem = nil
                    } label: {
                        Text("取消").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        fan.acknowledgeMismatch()
                        if let name = item.preset {
                            fan.apply(name)
                        } else {
                            fan.noteConfirmed()
                        }
                        disclaimerItem = nil
                    } label: {
                        Text("我已知晓风险并继续").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.bad)
                }
            }
            .padding(20)
            .frame(width: 430)
        }
    }

    private func modelStatusColor(_ s: ModelMatch) -> Color {
        switch s {
        case .matched: return Palette.ok
        case .undetected: return Palette.warn
        case .mismatched: return Palette.bad
        }
    }

    private func modelStatusLabel(_ s: ModelMatch) -> String {
        switch s {
        case .matched: return "机型匹配"
        case .undetected: return "机型待确认"
        case .mismatched: return "机型不匹配"
        }
    }

    private var currentPresetLabel: String {
        guard let name = fan.activePreset else { return "固件自动策略" }
        if name == "custom" { return "自定义曲线" }
        return fan.presets?.preset(name)?.label ?? name
    }

    /// 点「应用」档位：机型匹配或已确认风险 → 直接下发；否则先弹免责声明
    private func requestFanApply(_ name: String) {
        if fan.status == .matched || fan.acknowledgedMismatch {
            fan.apply(name)
        } else {
            disclaimerItem = DisclaimerItem(preset: name)
        }
    }

    private func fanStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.text)
                Text("RPM")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func presetRow(name: String, preset: FanPreset) -> some View {
        let active = fan.activePreset == name
        return HStack(spacing: 12) {
            FanCurveSparkline(curve: preset.cpu, highlighted: active)
                .frame(width: 92, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preset.label ?? name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    if active {
                        Text("使用中")
                            .font(.system(size: 8.5, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Palette.accent.opacity(0.18)))
                            .foregroundStyle(Palette.accent)
                    }
                }
                Text(preset.desc ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                requestFanApply(name)
            } label: {
                Group {
                    if fan.applying == name {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Text(active ? "重新下发" : "应用")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }
                .frame(width: 54)
                .padding(.vertical, 4)
                .background(Capsule().fill(Palette.accent.opacity(active ? 0.10 : 0.16)))
                .overlay(Capsule().stroke(Palette.accent.opacity(0.32), lineWidth: 0.8))
                .foregroundStyle(Palette.accent)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(fan.applying != nil || !fan.kextLoaded)
            .opacity(fan.kextLoaded ? 1 : 0.4)
            .help("写入这条曲线需要管理员授权")
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 风扇曲线缩略图

/// 把 8 个温度/占空比断点画成一条折线。
/// 不用 Canvas 的曲线平滑：这条线要能看出拐点，平滑后反而失真。
private struct FanCurveSparkline: View {
    let curve: FanCurve
    var highlighted: Bool

    var body: some View {
        Canvas { ctx, size in
            let n = curve.temp.count
            guard n > 1 else { return }
            func point(_ i: Int) -> CGPoint {
                let x = CGFloat(i) / CGFloat(n - 1) * size.width
                let duty = CGFloat(min(max(curve.duty[i], 0), 100)) / 100
                return CGPoint(x: x, y: size.height - duty * size.height)
            }
            var line = Path()
            for i in 0..<n {
                let p = point(i)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()

            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [Palette.accent.opacity(highlighted ? 0.22 : 0.10),
                                  Palette.accent.opacity(0)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(Palette.accent.opacity(highlighted ? 0.95 : 0.55)),
                       style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            for i in 0..<n {
                let p = point(i)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.4, y: p.y - 1.4, width: 2.8, height: 2.8)),
                         with: .color(Palette.accent.opacity(highlighted ? 0.95 : 0.5)))
            }
        }
    }
}

