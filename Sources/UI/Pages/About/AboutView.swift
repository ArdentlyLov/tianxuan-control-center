//
//  AboutView.swift
//  「关于」页：版本、作者、致谢
//

import SwiftUI
import AppKit

struct AboutView: View {
    @EnvironmentObject var store: SensorStore
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "关于", subtitle: "版本信息、更新记录与项目致谢。")
            brandCard

            SectionTitle(text: "更新日志", command: "changelog")
            whatsNewCard

            SectionTitle(text: "信息", command: "sysinfo --about")
            infoCard

            SectionTitle(text: "致谢", command: "credits")
            creditCard

            SectionTitle(text: "说明", command: "notes")
            disclaimerCard
        }
    }

    // MARK: - 更新日志

    /// 按卡片分组展示更新内容。
    private var whatsNewCard: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.releaseCards.enumerated()), id: \.offset) { _, group in
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(group.enumerated()), id: \.offset) { i, note in
                            if i > 0 { Divider().opacity(0.30) }
                            whatsNewRow(note.icon, note.title, note.detail)
                        }
                    }
                }
            }
        }
    }

    /// 每张卡放几条：卡太多会碎，太少又会退化成「一张巨卡」（见上面的注释）
    private static let releaseCards: [[(icon: String, title: String, detail: String)]] = {
        let all = releaseNotes
        var out: [[(icon: String, title: String, detail: String)]] = []
        var i = 0
        while i < all.count {
            out.append(Array(all[i..<min(i + 3, all.count)]))
            i += 3
        }
        return out
    }()

    private static let releaseNotes: [(icon: String, title: String, detail: String)] = [
        ("paintpalette", "更简洁的控制中心", "以中性灰、圆角卡片与蓝色强调重绘界面。CPU 与 GPU 并排展示，主要读数更加清晰，支持深色、浅色和跟随系统外观。"),
        ("shield.lefthalf.filled", "TIANXUAN 品牌标识", "侧栏使用简洁的图形徽记，关于页展示完整 TIANXUAN 徽标，统一界面中的品牌呈现。"),
        ("slider.horizontal.3", "熟悉的控制，更清晰的状态", "概览提供性能与键盘灯效快捷入口；功耗、风扇、温度与设备能力继续根据真实硬件读数显示。")
    ]

    private func whatsNewRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 品牌

    private var brandCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                if let artwork = Self.brandArtwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: 210)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                        .accessibilityLabel("TIANXUAN 品牌徽标")
                }
                classicBrandRow.padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private static let brandArtwork: NSImage? = {
        guard let url = Bundle.main.url(forResource: "TianxuanBrand", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private var classicBrandRow: some View {
        HStack(spacing: 18) {
            if Self.brandArtwork == nil {
                Image(nsImage: Self.brandIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(AppInfo.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Pill(text: AppInfo.displayVersion, color: Palette.accent)
                }
                Text(AppInfo.englishName)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                Text(AppInfo.tagline)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 8)
            copyVersionButton
        }
    }

    /// 程序图标（摊平成单张位图）。
    /// ⚠️ 直接把 `NSApp.applicationIconImage` 塞进 `Image(nsImage:)`，会让 `ImageRenderer`
    /// 把**整页**渲染成一张全透明空图（只在离屏出图时发作，窗口里正常）。
    /// 先用位图上下文重画一遍再交给 SwiftUI，就没事了。
    static let brandIcon: NSImage = {
        let src = NSApp.applicationIconImage
            ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let side: CGFloat = 128
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(side), pixelsHigh: Int(side),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return src }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        src.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let flat = NSImage(size: NSSize(width: side, height: side))
        flat.addRepresentation(rep)
        return flat
    }()

    private var copyVersionButton: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(AppInfo.oneLine, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
            } label: {
                Text(copied ? "已复制" : "复制版本信息")
            }
            .buttonStyle(GrayButtonStyle())
        }
    }

    // MARK: - 信息

    private var infoCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                LabelValue(label: "版本", value: "\(AppInfo.displayVersion)  (build \(AppInfo.build))")
                LabelValue(label: "作者", value: AppInfo.author, mono: false)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("GitHub")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 108, alignment: .leading)
                    Button {
                        open(AppInfo.githubURL)
                    } label: {
                        Text(AppInfo.githubDisplay)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("打开 \(AppInfo.githubURL)")
                    Spacer(minLength: 0)
                }
                LabelValue(label: "构建时间", value: AppInfo.buildDateText)
                LabelValue(label: "系统", value: AppInfo.osVersion)
                LabelValue(label: "机型",
                           value: store.hardware.productName.isEmpty
                                  ? store.hardware.modelCode
                                  : "\(store.hardware.productName)  [\(store.hardware.modelCode)]",
                           mono: false)
                LabelValue(label: "处理器", value: store.hardware.cpu, mono: false)
            }
        }
    }

    // MARK: - 致谢

    private var creditCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                creditRow(icon: "wand.and.stars",
                          title: "灵感参考",
                          name: "\(AppInfo.helperName)  ·  \(AppInfo.helperAuthor)",
                          detail: "风扇曲线、性能模式、MUX、充电上限这些功能的取舍，以及对 ASUS ACPI/WMI 的理解，都来自这个 Windows 项目。本程序是 macOS 上的独立重写。",
                          action: ("打开项目", { open(AppInfo.helperURL) }))

                Divider().opacity(0.35)

                creditRow(icon: "paintpalette",
                          title: "UI 灵感",
                          name: AppInfo.uiInspiration,
                          detail: "以简洁的图形徽记、克制的蓝色与圆角卡片呈现设备状态，优先突出实时读数与操作。",
                          action: nil)

                Divider().opacity(0.35)

                creditRow(icon: "bolt.fill",
                          title: "EC 灯效修复思路",
                          name: "angus666888",
                          detail: "提供 EC 层灯效修复思路，本项目的键盘背光 / Aura 通道握手因此得以在 macOS 上正确工作。",
                          action: ("打开主页", { open("https://github.com/angus666888?tab=repositories") }))

                Divider().opacity(0.35)

                creditRow(icon: "display",
                          title: "可选 NVIDIA 功耗数据源",
                          name: "zzzyy678 · SMCNvidiaGPU",
                          detail: "兼容该项目提供的 NVIDIA 功耗及显存读数。显存占用与容量也可直接读取显卡驱动；实际显示以当前驱动提供的数据为准。",
                          action: ("打开项目", { open("https://github.com/zzzyy678/SMCNvidiaGPU") }))
            }
        }
    }

    private func creditRow(icon: String, title: String, name: String,
                           detail: String, action: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 10))
                        .tracking(0.6)
                        .foregroundStyle(Palette.textTertiary)
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.text)
                }
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(GrayButtonStyle())
            }
        }
    }

    // MARK: - 说明

    private var disclaimerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("本程序与 ASUSTeK 无关，也不是官方软件。所有硬件访问都走 macOS 已有的通道：AppleSMC（VirtualSMC + AsusSMC）、IORegistry、IOHID、libproc，不注入任何内核代码。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Pill(text: "GPL-3.0 License", color: Palette.textSecondary)
                    Pill(text: "x86_64 + arm64", color: Palette.textSecondary)
                    Pill(text: "已采样 \(store.sampleCount) 次", color: Palette.textTertiary)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
