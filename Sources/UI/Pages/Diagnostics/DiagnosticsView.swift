// DiagnosticsView.swift

import SwiftUI
import AppKit
import Combine

// MARK: - 诊断

struct DiagnosticsView: View {
    @EnvironmentObject var store: SensorStore
    @State private var showKeys = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "能力矩阵", trailing: "实时探测")

            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.capabilities.enumerated()), id: \.element.id) { idx, cap in
                        CapabilityRow(cap: cap)
                        if idx < store.capabilities.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }

            SectionTitle(text: "数据来源")
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(DataSourceCatalog.all.enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 10) {
                            Text(item.metric)
                                .font(.system(size: 11.5, weight: .medium))
                                .frame(width: 92, alignment: .leading)
                            Text(item.channel)
                                .font(.system(size: 10.5).monospaced())
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 250, alignment: .leading)
                            Text(item.needsKext ? "依赖 kext" : "无需 kext")
                                .font(.system(size: 10))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill((item.needsKext ? Palette.warn : Palette.ok).opacity(0.13)))
                                .foregroundStyle(item.needsKext ? Palette.warn : Palette.ok)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        if idx < DataSourceCatalog.all.count - 1 { Divider().opacity(0.35) }
                    }
                }
            }

            SectionTitle(text: "硬件与驱动")
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    LabelValue(label: "商品名", value: store.hardware.productName.isEmpty ? "—" : store.hardware.productName)
                    LabelValue(label: "海外名", value: store.hardware.globalName.isEmpty ? "—" : store.hardware.globalName)
                    LabelValue(label: "机型代码", value: store.hardware.modelCode.isEmpty ? "—" : store.hardware.modelCode)
                    LabelValue(label: "名称来源", value: store.hardware.nameSource)
                    LabelValue(label: "厂商", value: store.hardware.vendor)
                    LabelValue(label: "处理器", value: store.hardware.cpu)
                    LabelValue(label: "线程数", value: "\(store.hardware.cores)")
                    LabelValue(label: "内存", value: String(format: "%.0f GB", store.hardware.ramGB))
                    LabelValue(label: "系统", value: store.hardware.osVersion)
                    ForEach(store.hardware.gpus) { gpu in
                        LabelValue(label: "显卡", value: "\(gpu.name) — \(gpu.driver)")
                    }
                    LabelValue(label: "内核扩展", value: store.kexts.summary)
                    LabelValue(label: "SMC 键数量", value: "\(store.keyNames.count)")
                    LabelValue(label: "采样间隔", value: "\(store.samplingRate.longLabel) · \(store.samplingRate.summary)")
                    LabelValue(label: "已完成采样", value: "\(store.sampleCount) 次")
                    LabelValue(label: "用户", value: Admin.isRoot ? "root（可直接写 SMC）" : "普通用户（写入需授权）")
                }
            }

            HStack(spacing: 8) {
                Button {
                    copyReport()
                } label: {
                    Text(copied ? "已复制" : "复制诊断报告")
                }
                .buttonStyle(GrayButtonStyle(prominent: true))

                Button {
                    showKeys.toggle()
                } label: {
                    Text(showKeys ? "隐藏 SMC 键" : "查看全部 SMC 键")
                }
                .buttonStyle(GrayButtonStyle())

                if showKeys {
                    Button {
                        store.reloadAllReadings()
                    } label: {
                        Text("刷新读数")
                    }
                    .buttonStyle(GrayButtonStyle())
                }
                Spacer()
            }

            if showKeys {
                Card(padding: 12) {
                    if store.readings.isEmpty {
                        Text("正在读取…")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 6)], spacing: 4) {
                                ForEach(store.readings, id: \.key) { r in
                                    HStack(spacing: 6) {
                                        Text(r.key)
                                            .font(.system(size: 10).monospaced())
                                            .foregroundStyle(Palette.accent)
                                        Text(r.display)
                                            .font(.system(size: 10).monospacedDigit())
                                        Spacer(minLength: 0)
                                        Text(r.type.trimmingCharacters(in: .whitespaces))
                                            .font(.system(size: 8.5).monospaced())
                                            .foregroundStyle(Palette.textTertiary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(height: 260)
                    }
                }
                .onAppear {
                    if store.readings.isEmpty { store.reloadAllReadings() }
                }
            }
        }
    }

    private func copyReport() {
        var lines: [String] = []
        lines.append("天选控制中心 诊断报告")
        lines.append("机型: \(store.hardware.modelName) (\(store.hardware.modelCode))")
        lines.append("CPU: \(store.hardware.cpu) / \(store.hardware.cores) 线程")
        lines.append("系统: \(store.hardware.osVersion)")
        lines.append("驱动: \(store.kexts.summary)")
        lines.append("SMC 键: \(store.keyNames.count)")
        lines.append("")
        for cap in store.capabilities {
            lines.append("[\(cap.status.badge)] \(cap.title): \(cap.summary)")
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines.joined(separator: "\n"), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }
}

