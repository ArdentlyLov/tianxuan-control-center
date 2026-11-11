import SwiftUI
import AppKit

struct RepairGuideView: View {
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "适配说明", subtitle: "天选 3 酷睿版 FX507ZM 的实际修复方案、复现步骤与验证方法。")
            HStack(spacing: 10) {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    copied = pasteboard.setString(FX507ZMRepairGuide.copyText, forType: .string)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "已复制完整方案" : "复制完整方案", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(GrayButtonStyle(prominent: true))
                .accessibilityIdentifier("repairGuide.copy")

                Button {
                    PageRouter.shared.jump(to: .diagnostics)
                } label: {
                    Label("查看本机诊断", systemImage: "stethoscope")
                }
                .buttonStyle(GrayButtonStyle())
                .accessibilityIdentifier("repairGuide.diagnostics")
                Spacer(minLength: 0)
            }

            summaryCard
            driversCard

            ForEach(FX507ZMRepairGuide.sections) { section in
                RepairGuideSectionCard(section: section)
            }

            sourcesCard
        }
        .textSelection(.enabled)
    }

    private var summaryCard: some View {
        Card(accent: Palette.accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .padding(12)
                        .background(Palette.panelHi, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("这台天选 3 是怎样修好的")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Palette.text)
                        Text(FX507ZMRepairGuide.hardware)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        Text("实机记录 · \(FX507ZMRepairGuide.verifiedDate)")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.accent)
                    }
                    Spacer(minLength: 0)
                }

                Text(FX507ZMRepairGuide.summary)
                    .guideBody()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 8)], alignment: .leading, spacing: 8) {
                    channelLabel("双风扇", "ASUS WMI", icon: "fanblades")
                    channelLabel("CPU 温度", "Intel / SMC", icon: "thermometer.medium")
                    channelLabel("频率与功耗", "Intel Power Gadget", icon: "cpu")
                }

                Text(FX507ZMRepairGuide.system)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(FX507ZMRepairGuide.scope)
                    .guideBody(color: Palette.textSecondary)
            }
        }
    }

    private func channelLabel(_ title: String, _ channel: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.text)
                Text(channel).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.subtle, in: RoundedRectangle(cornerRadius: 10))
    }

    private var driversCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "本机驱动与版本", trailing: "记录于 \(FX507ZMRepairGuide.verifiedDate)")
                Text(FX507ZMRepairGuide.driverNote).guideBody(color: Palette.textSecondary)

                ForEach(FX507ZMRepairGuide.drivers) { driver in
                    if driver.id != FX507ZMRepairGuide.drivers.first?.id { Divider().opacity(0.5) }
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(driver.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(driver.version)
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(Palette.accent)
                        }
                        .frame(width: 174, alignment: .leading)
                        Text(driver.purpose).guideBody(color: Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var sourcesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "来源与核验依据")
                Text(FX507ZMRepairGuide.evidence).guideBody(color: Palette.textSecondary)
                ForEach(FX507ZMRepairGuide.references) { reference in
                    Link(destination: reference.url) {
                        Label(reference.title, systemImage: "arrow.up.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                Divider().opacity(0.5)
                Text(FX507ZMRepairGuide.license).guideBody(color: Palette.textSecondary)
            }
        }
    }
}

private struct RepairGuideSectionCard: View {
    let section: FX507ZMRepairGuide.GuideSection
    @State private var expanded = false

    var body: some View {
        Card {
            if section.collapsedByDefault {
                DisclosureGroup(isExpanded: $expanded) {
                    sectionContent.padding(.top, 14)
                } label: {
                    Text(section.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(text: section.title)
                    sectionContent
                }
            }
        }
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(section.intro).guideBody(color: Palette.textSecondary)
            ForEach(section.entries) { entry in
                if entry.id != section.entries.first?.id { Divider().opacity(0.5) }
                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.detail).guideBody()
                    if let command = entry.command {
                        Text(command)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.subtle, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private extension Text {
    func guideBody(color: Color = Palette.text) -> some View {
        self.font(.system(size: 12))
            .foregroundStyle(color)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
