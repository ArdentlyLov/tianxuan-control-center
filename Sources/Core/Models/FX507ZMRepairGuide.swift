import Foundation

/// 已核实的实机记录。页面和剪贴板共用内容，记录日期与当前设备状态分开。
enum FX507ZMRepairGuide {
    struct Driver: Identifiable {
        let name: String
        let version: String
        let purpose: String
        var id: String { name }
    }

    struct Entry: Identifiable {
        let title: String
        let detail: String
        var command: String? = nil
        var commandLanguage: String = "bash"
        var id: String { title }
    }

    struct GuideSection: Identifiable {
        let id: String
        let title: String
        let intro: String
        let entries: [Entry]
        var collapsedByDefault: Bool = false
    }

    struct Reference: Identifiable {
        let title: String
        let url: URL
        var id: String { url.absoluteString }
    }

    static let title = "天选 3 FX507ZM 黑苹果适配说明"
    static let verifiedDate = "2026-11-10"
    static let hardware = "FX507ZM · Core i7-12700H · RTX 3060 Laptop"
    static let system = "macOS 26.7.1（25G241）· Darwin 25.6.0 · x86_64"
    static let summary = "这台天选 3 的修复分为两条读取通道：VelaAsusWMI 1.0.2 恢复 ASUS 固件接口与双风扇反馈；Intel Power Gadget / EnergyDriver 3.7.0 提供 CPU 温度、频率和封装功耗。应用根据实际能力显示读数。"
    static let scope = "以下是上述机器在记录日期的实测方案。同型号部署仍需核对 BIOS、ACPI 与 macOS 版本。MacBookPro16,2 是 OpenCore 的 SMBIOS 伪装，物理型号应以机身、BIOS 和 ASUS 设备信息为准；FX507ZC、FX507ZR 及锐龙版需要各自验证。"
    static let driverNote = "这是修复机器当时加载的组合。风扇读取的关键是 VelaAsusWMI；CPU 频率和功耗读取的关键是 Intel Power Gadget 框架与 EnergyDriver。其余项目属于这台黑苹果的基础环境或其他控制通道，按目标机器的 EFI 配置核对。"

    static let drivers: [Driver] = [
        .init(name: "VelaAsusWMI", version: "1.0.2", purpose: "ASUS WMI / WMNB：CPU、GPU 风扇转速，固件性能策略、键盘与充电能力。运行服务协议版本为 2。"),
        .init(name: "Intel Power Gadget / EnergyDriver", version: "3.7.0", purpose: "框架与内核扩展配合，读取 CPU 温度、平均有效频率、最高核心频率和封装功耗。EnergyDriver 位于 /Library/Extensions。"),
        .init(name: "Lilu", version: "1.7.3", purpose: "本机 EFI 的基础补丁框架，为依赖它的插件提供支持。"),
        .init(name: "VirtualSMC", version: "1.3.9", purpose: "提供 AppleSMC 兼容服务，让应用读取可用的 SMC 传感器。"),
        .init(name: "SMCProcessor / SMCSuperIO", version: "1.3.9 / 1.3.9", purpose: "本机已加载的 SMC 传感器插件。CPU 温度可回退至 SMC；本机 FNum 为 0，双风扇实际来自 ASUS WMI。"),
        .init(name: "CpuTopologyRebuild / CpuTscSync", version: "2.0.2 / 1.1.3", purpose: "本机 Alder Lake 混合核心拓扑与时钟同步配置，需结合目标机器的 ACPI 和启动参数使用。"),
        .init(name: "VelaMSR", version: "1.0.0", purpose: "本机同时加载的 MSR 访问驱动，供独立的 CPU 寄存器控制方案使用；本页的频率监测使用 Intel Power Gadget。"),
        .init(name: "RestrictEvents", version: "1.1.7", purpose: "本机 EFI 中的兼容性插件。CPUFriend 在记录时未加载。")
    ]

    static let sections: [GuideSection] = [
        .init(id: "channels", title: "数据是怎样恢复的", intro: "风扇、CPU 传感器与性能控制分别核对自己的通道。", entries: [
            .init(title: "双风扇：ASUS WMI", detail: "驱动通过 WMNB 读取 CPU 风扇设备 0x00110013 与 GPU 风扇设备 0x00110014。应用选择已经完成固件探测的服务，固定每 500 ms 读取真实转速。有效的 0 RPM 表示停转；读取失败显示不可用。"),
            .init(title: "CPU：Intel Power Gadget + SMC 回退", detail: "应用动态加载 /Library/Frameworks/IntelPowerGadget.framework/Versions/A/IntelPowerGadget，通过 PG_Initialize、PG_ReadSample 等接口采样。平均有效频率、最高核心频率与封装功耗使用相邻两次有效采样；CPU 温度可回退到 AppleSMC。首次采样需要等待，缺失的数据不填估算值。"),
            .init(title: "性能模式：ASUS 固件策略", detail: "FX507ZM 的静音、平衡、增强使用 ASUS WMI 的 OEM 性能策略。选择这些预设时不会同时写入自定义风扇曲线。转速和频率随负载、温度与供电变化，增强模式没有固定的 RPM 或 GHz 保证。"),
            .init(title: "GPU 指标按实际能力显示", detail: "双风扇读取成功不代表独显的所有传感器可用。记录时 GPU 功耗、GPU 核心频率未由当前驱动提供，应用应显示不可用。其他机型的 SMCAsusFan、G815LM EC / MMIO 地址和曲线不能用于 FX507ZM。")
        ]),
        .init(id: "installation", title: "同型号复现步骤", intro: "先用测试 USB EFI 验证读取，再把通过验证的驱动加入日常启动配置。", entries: [
            .init(title: "1. 核对型号，保留可启动的 EFI", detail: "确认物理型号为 FX507ZM、CPU 为 i7-12700H。备份当前 EFI/OC/config.plist 与 Kexts，保留可启动的 USB EFI 作为回退。保留自己的 ACPI、序列号和平台配置，不复制他人的整份 EFI。"),
            .init(title: "2. 构建修复后的 WMI 1.0.2", detail: "在项目根目录执行以下命令。产物是 build/Drivers/VelaAsusWMI.kext，架构为 x86_64。Xcode 的「天选控制中心」scheme 也会编译驱动；构建不会安装或加载它。不要再使用造成启动循环的 1.0.0。", command: "bash Drivers/VelaAsusWMI/build.sh\npython3 Tests/DriverBuildTests.py"),
            .init(title: "3. 用测试 USB EFI 启动验证", detail: "将目标机器原本可启动的 EFI 复制到另一份测试 USB，把 VelaAsusWMI 1.0.2 放入测试 EFI/OC/Kexts，并按第 5 步添加、启用唯一的 WMI 条目。用对应 OpenCore 的 ocvalidate 检查后，从测试 USB 启动，保留原来的日常 EFI 作为回退。确认加载版本、系统稳定与后续读数。已有正常加载的 1.0.2 可直接检查当前服务。历史临时加载工具只支持配套 build 104，当前应用应使用这条 USB 验证路径。"),
            .init(title: "4. 主动读取固件接口", detail: "驱动启动和应用连接只读取服务属性，不在启动时执行 _WDG 等固件方法。首次验证时在「性能与风扇」点击「读取固件接口」，或运行下面的只读探测命令，然后确认 WMNB、两个风扇和实际转速。命令按应用安装在 /Applications 举例，其他位置请替换路径。", command: "\"/Applications/天选控制中心.app/Contents/MacOS/AsusControl\" wmi probe"),
            .init(title: "5. 验证通过后持久启用", detail: "将测试通过的同一份 VelaAsusWMI.kext 与配置移入日常 EFI。Kernel → Add 的条目如下；测试 USB 上启用该条目进行验证，日常 EFI 在验证通过后才启用。项目的 EFI 准备、安装工具保留 Enabled=false 的默认值，需按验证结果手动调整。用对应 OpenCore 版本的 ocvalidate 核对配置，重启后再次检查加载版本和读数。", command: "BundlePath      = VelaAsusWMI.kext\nExecutablePath  = Contents/MacOS/VelaAsusWMI\nPlistPath       = Contents/Info.plist\nArch            = x86_64\nMinKernel       = 22.0.0\nMaxKernel       = （留空）\nEnabled         = true", commandLanguage: "text"),
            .init(title: "6. 安装 CPU 监测依赖", detail: "本机使用 Intel Power Gadget / EnergyDriver 3.7.0。使用适合目标 Intel macOS 的安装包，按安装器和系统扩展授权流程完成安装，必要时重启。核对 IntelPowerGadget.framework 与 /Library/Extensions/EnergyDriver.kext 同时存在且驱动已加载；只复制框架不能完成 CPU 频率和功耗读取。EnergyDriver 在本机不属于 OpenCore 的 Kernel → Add。"),
            .init(title: "7. 安装应用，核对监控，再逐项测试控制", detail: "构建并打开天选控制中心，在「诊断」核对设备与能力，在「监控」观察 CPU 温度、平均频率、最高核心频率和功耗。只读验证通过后逐项测试平衡、静音、增强以及背光等已公开能力。若启动或加载失败，从回退 EFI 启动，恢复备份或关闭新 WMI 条目，再排查驱动副本与版本。")
        ]),
        .init(id: "verification", title: "验证命令与本机结果", intro: "以下结果来自 2026-11-10 的只读检查，数值是一次采样记录，不是目标值。", entries: [
            .init(title: "检查真正加载的版本", detail: "kmutil 应列出 VelaAsusWMI 1.0.2 与 EnergyDriver 3.7.0。当前活动 EFI 已启用 VelaAsusWMI 1.0.2；/Library/Extensions 中也存在 WMI 副本，不能仅凭 EFI 条目判断实际加载来源。源码、bundle 与完整运行服务的版本均核对为 1.0.2，旧文档中的「1.0.3」已更正。", command: "kmutil showloaded | grep -E 'VelaAsusWMI|EnergyDriver|VirtualSMC|SMCProcessor|SMCSuperIO'"),
            .init(title: "检查完成探测的 WMI 服务", detail: "本机完整服务的 DriverVersion=1.0.2、ProtocolVersion=2、FirmwareProbed=Yes、FirmwareProbeState=complete、WMIManagementMethod=WMNB，CPUFanDevice=1114131，GPUFanDevice=1114132。ReadOnlyAtBoot 与 NoFirmwareCallsAtBoot 均为 Yes。", command: "ioreg -r -c VelaAsusWMI -l"),
            .init(title: "检查应用实际选择的读取通道", detail: "wmi 报告风扇反馈 2 个。status 的一次采样为 CPU 63°C、CPU 风扇 3400 RPM、GPU 风扇 3200 RPM，风扇通道是华硕 WMI。sensors 报告 WMI 可读 2 / 声明 2，SMC FNum=0。请观察多次采样和负载变化；缺失读数需要排查对应通道。", command: "\"/Applications/天选控制中心.app/Contents/MacOS/AsusControl\" wmi\n\"/Applications/天选控制中心.app/Contents/MacOS/AsusControl\" status\n\"/Applications/天选控制中心.app/Contents/MacOS/AsusControl\" sensors"),
            .init(title: "检查 CPU 频率与功耗", detail: "本轮使用应用同一 IntelPowerProbe 完成 5 次只读采样：CPU 温度 56–63°C，平均有效频率 1.511–2.180 GHz，最高核心频率 3.700 GHz，封装功耗 20.67–31.22 W。它们是当时负载下的实测值。其他机器在「监控」等待至少两次采样，确认这些指标有实际值且会变化。CLI 的 status / sensors 当前不完整输出 CPU 频率，应结合界面验证。")
        ]),
        .init(id: "repairs", title: "旧驱动为何失败，1.0.2 修了什么", intro: "这些修正来自本机加载日志与实际 ACPI 方法核对。", entries: [
            .init(title: "1.0.0：启动循环与 ACPI 类型符号", detail: "旧驱动直接引用 IOACPIPlatformDevice::metaClass，启动日志中该符号被解析为地址零。修复改为运行时按类名核对对象类型；构建检查拒绝未定义的 ACPI metaclass 引用。"),
            .init(title: "1.0.1：AppleACPIPlatform 依赖被拒绝", detail: "临时加载在依赖检查阶段以退出码 71 被拒绝，未进入驱动启动。本机 AppleACPIPlatform 的版本与最低兼容版本均为 6.1，旧依赖声明 1.0.0 不兼容。1.0.2 删除不需要的 ACPI 链接依赖，保留 IOKit、libkern、mach；ACPI 方法通过已匹配对象的虚方法调用。"),
            .init(title: "WMNB 参数固定为 20 字节", detail: "FX507ZM 的 WMNB 无条件创建 IIA0…IIA4，因此每个请求都必须提供 20 字节缓冲，不能只按单次有效载荷长度传参。"),
            .init(title: "曲线返回接受 32 字节固件填充", detail: "本机曲线方法返回 32 字节，其中前 16 字节为有效曲线数据，其余为固件填充。驱动接受这种返回格式；普通 OEM 性能预设继续只切换固件策略。"),
            .init(title: "启动阶段保持被动连接", detail: "驱动启动不执行固件方法，应用连接只读服务属性；用户主动探测后才读取固件能力。本机现在已加载 1.0.2 并完成 WMNB、风扇与控制能力验证。冷启动、睡眠唤醒和长期稳定性仍需在每台目标机器测试，不能由一次成功读取推断全部验证完成。")
        ], collapsedByDefault: true),
        .init(id: "troubleshooting", title: "常见问题", intro: "根据缺失的指标定位到对应驱动与接口。", entries: [
            .init(title: "风扇没有读数，但 AppleSMC 已连接", detail: "本机双风扇来自 WMI，SMC FNum=0 是已记录的状态。先查 VelaAsusWMI 是否加载，再主动读取固件接口，确认应用选择的是 FirmwareProbed=Yes 且管理方法为 WMNB 的完整服务。"),
            .init(title: "ioreg 中有多个 WMI 服务，部分未探测", detail: "本机也存在没有管理 GUID 或尚未探测的 WMI 服务。查看完整服务的能力与应用 wmi 输出，不要用任意一个 FirmwareProbed=No 条目判断全部失败。"),
            .init(title: "温度能读，CPU 频率或功耗不可用", detail: "温度可能来自 SMC 回退。核对 Intel Power Gadget 框架版本与 EnergyDriver 是否加载，等待至少两次有效采样，并在监控页确认数据。VelaAsusWMI 不提供这条 Intel CPU 采样链路。"),
            .init(title: "驱动加载失败或重启后版本不对", detail: "核对 EFI 的 Enabled、BundlePath、ExecutablePath 与实际 bundle 版本，以及 /Library/Extensions 中是否存在旧副本。退出码 71 对应依赖检查问题，不等同于固件探测失败。先用可启动的 EFI 恢复系统，再检查日志。"),
            .init(title: "历史临时加载工具拒绝当前应用", detail: "Tools/test_runtime.py 显式要求修正版 WMI 1.0.2、配套应用 build 104，以及实际 EFI 中关闭的 WMI 条目。它是早期分阶段加载的验证工具，不能直接搭配当前 build 106。只有保留了配套历史验证包时才使用该流程；当前版本按本页的测试 USB EFI 步骤验证。"),
            .init(title: "增强模式下频率低，或风扇未超过 4000 RPM", detail: "OEM 增强模式调节固件性能策略。频率低应结合 CPU 负载、温度、供电与 XCPM 状态排查；仅需读取传感器时无需引入最低频率控制器。风扇 RPM 由固件和温度决定。")
        ], collapsedByDefault: true),
        .init(id: "power", title: "CPU 电源策略的独立修复记录", intro: "下面的 XCPM / HWP 控制器属于另一项本地部署，不包含在本应用安装内容里。", entries: [
            .init(title: "持续低频与旧 yes 回退", detail: "2026-11-08 新控制器曾被 watchdog 停用；11 月 10 日登录时旧回退启动了 20 个 yes。原故障根因没有完整记录。11 月 10 日修订部署后，241 秒、432 次采样中 yes 始终为 0，机主反馈操作流畅。"),
            .init(title: "当前 XCPM / HWP 实测", detail: "XCPM mode=1，X86PlatformPlugin / Shim 与 /dev/xcpm 可用。交互时 P-core 最低 HWP 请求为 40，E-core 允许 4 或 40；空闲时全部 20 个逻辑核心回到 4。HWP 请求单位不能直接换算为 GHz。报告中的交互平均实测频率为 3.020 GHz，空闲为 1.798 GHz，并非固定全核频率。"),
            .init(title: "适用边界", detail: "控制器部署在 /Library/Application Support/CodexXCPM；记录时 CPUFriend 未加载，也未采用 EPP 32。冷启动、睡眠唤醒、电池切换与长期稳定性尚未完成验证，旧故障回退仍保留。此方案需要独立部署与验证，本页不把它列为读取温度、频率和风扇的必需依赖。")
        ], collapsedByDefault: true)
    ]

    static let references: [Reference] = [
        .init(title: "Linux ASUS WMI", url: URL(string: "https://github.com/torvalds/linux/blob/master/drivers/platform/x86/asus-wmi.c")!),
        .init(title: "G-Helper TUF ACPI 接口", url: URL(string: "https://github.com/seerge/g-helper/blob/main/app/AsusACPI.cs")!),
        .init(title: "原项目 Vela-X", url: URL(string: "https://github.com/Xelon233/Vela-X")!)
    ]
    static let evidence = "核验依据：本机 kmutil、VelaAsusWMI IORegistry、活动 EFI 的必要驱动条目、Intel Power Gadget 安装信息、应用只读 CLI、IntelPowerProbe 实机采样，以及 2026-11-10 XCPM 修订部署报告。完整 ACPI、EFI 平台私有信息与账户凭据不随指南分发。"
    static let license = "保留原作者 Xelon Jangs（Xelon233）署名与 GPLv3 许可。上游为 GPLv3 第 3 版（不含「或后续版本」），本修改版整体按 GPLv3 发布。"

    static var copyText: String {
        var lines = ["# \(title)", "", "验证日期：\(verifiedDate)", "", hardware, "", system, "", summary, "", scope,
                     "", "## 本机驱动与版本", "", driverNote, ""]
        for driver in drivers {
            lines.append("- \(driver.name) \(driver.version)：\(driver.purpose)")
        }
        for section in sections {
            lines += ["", "## \(section.title)", "", section.intro]
            for entry in section.entries {
                lines += ["", "### \(entry.title)", "", entry.detail]
                if let command = entry.command {
                    lines += ["", "```\(entry.commandLanguage)", command, "```"]
                }
            }
        }
        lines += ["", "## 来源与核验依据", "", evidence, ""]
        lines += references.map { "- [\($0.title)](\($0.url.absoluteString))" }
        lines += ["", license, ""]
        return lines.joined(separator: "\n")
    }
}
