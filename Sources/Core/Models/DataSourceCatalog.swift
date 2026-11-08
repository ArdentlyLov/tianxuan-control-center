//
//  DataSourceCatalog.swift
//  诊断页用：每个指标到底走哪条通道、要不要依赖 kext
//

import Foundation

struct DataSourceItem: Identifiable {
    let id = UUID()
    let metric: String
    let channel: String
    let needsKext: Bool
}

enum DataSourceCatalog {
    static let all: [DataSourceItem] = [
        .init(metric: "CPU 温度", channel: "Intel Power Gadget / EnergyDriver；AppleSMC · TC0P／TC0F／TC0D／TC0E", needsKext: true),
        .init(metric: "CPU 频率", channel: "Intel Power Gadget / EnergyDriver；AMD AMDRyzenCPUPowerManagement", needsKext: true),
        .init(metric: "CPU 功耗", channel: "Intel Power Gadget / EnergyDriver；AMD AMDRyzenCPUPowerManagement（整包）", needsKext: true),
        .init(metric: "风扇转速", channel: "华硕 WMI 固件反馈 → AppleSMC；G815LM 可回退 EC tach（逐路检测）", needsKext: true),
        .init(metric: "环境光", channel: "AppleSMC · ALV0", needsKext: true),
        .init(metric: "键盘背光", channel: "Aura HID · report 0x5A", needsKext: false),
        .init(metric: "CPU 负载", channel: "Mach host_processor_info", needsKext: false),
        .init(metric: "热压力", channel: "ProcessInfo.thermalState", needsKext: false),
        .init(metric: "内存占用", channel: "Mach host_statistics64", needsKext: false),
        .init(metric: "电池", channel: "IOKit AppleSmartBattery", needsKext: false),
        .init(metric: "显卡驱动", channel: "IORegistry · CFBundleIdentifier", needsKext: false),
        .init(metric: "显卡功耗", channel: "IORegistry PerformanceStatistics；可选 NVIDIA sysctl 功耗（mW → W）", needsKext: true),
        .init(metric: "GPU 核心频率", channel: "IORegistry PerformanceStatistics 核心时钟（MHz / Hz），需驱动提供", needsKext: true),
        .init(metric: "显存占用", channel: "IORegistry PerformanceStatisticsAccum 已用显存 + PCI 容量；可选 NVIDIA sysctl（MiB）", needsKext: true)
    ]
}
