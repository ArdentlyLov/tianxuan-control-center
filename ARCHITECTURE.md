# 天选控制中心架构

应用名称：天选控制中心 / Tianxuan Control Center。当前版本 2.4.28（106）。

## 责任与目录

| 目录 | 责任 | 代表文件 |
| --- | --- | --- |
| `Sources/App` | 进程入口、生命周期、CLI、品牌与版本 | `main.swift`、`TianxuanControlApp.swift`、`AppDelegate.swift`、`CLI.swift` |
| `Sources/Core/Models` | 状态、机型、曲线和功耗模型 | `EditableCurve.swift`、`PowerProfile.swift`、`HardwareIdentity.swift` |
| `Sources/Core/Control` | 操作协调、反馈确认、控制状态 | `ThermalControl.swift`、`FanPresetApplication.swift`、`PowerLimitController.swift` |
| `Sources/Core/Monitoring` | 后台采样与快照 | `FanProbe.swift`、`SensorStore.swift` |
| `Sources/Core/Preferences` | GUI 与 CLI 共用偏好 | `Prefs.swift` |
| `Sources/Hardware` | 设备发现、协议报文和读写接口 | `ASUS/ASUSWMI.swift`、`SMC/SMCBridge.c`、`Intel/IntelPowerProbe.swift` |
| `Sources/Services` | 操作系统服务及授权 | `Authorization/Admin.swift`、`Startup/LaunchAtLogin.swift` |
| `Sources/UI/Pages` | 按功能分组的 SwiftUI 页面 | `Performance/PerformanceView.swift`、`Overview/OverviewView.swift` |
| `Sources/UI/Navigation`、`Shell` | 导航与窗口装配 | `PageRouter.swift`、`SidebarView.swift`、`ContentView.swift` |
| `Sources/UI/Components`、`Theme`、`MenuBar` | 共享控件、视觉主题与菜单栏 | `Card.swift`、`Palette.swift`、`MenuBarView.swift` |
| `Drivers` | 独立的内核驱动源代码 | `VelaAsusWMI` |

页面使用控制器提供的状态并调用控制操作。控制器协调硬件和系统服务；硬件层提供协议和实际读数，不承载 SwiftUI 页面。App 负责连接生命周期、服务与 UI。

原 `Views.swift`、`UIComponents.swift`、`App.swift`、`CustomCurve.swift`、`PowerLimit.swift`、`Privileged.swift` 中混放的页面、模型和操作已分别拆到上述目录。

## 构建与验证

```sh
./build.sh x86_64
bash Tests/run.sh
xcodebuild -project '天选控制中心.xcodeproj' -scheme '天选控制中心' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

命令行脚本递归编译 Sources。Xcode Sources 分组和编译阶段与目录保持一致；添加新文件时需同步工程。SMC 的 C 桥接位于 `Sources/Hardware/SMC`。

## 运行约定

- 普通 OEM 风扇档位只应用固件策略，避免同时额外写自定义曲线。
- 模式写入成功与固件反馈一致后才确认；过期的后台读取不能覆盖新选择。
- 风扇独立每 500 毫秒采样。CPU 平均频率与最高核心频率分开显示；传感器失效时不显示假值。
- 没有已验证的 CPU 最低频率锁定接口，不保证持续高于 1.5 或 2 GHz。
- 驱动构建与安装分离；应用重构和改名不会修改 EFI 或重新加载驱动。
