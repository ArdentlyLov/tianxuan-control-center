# 天选控制中心 / Tianxuan Control Center

> macOS 上的华硕笔记本控制中心，[G-Helper](https://github.com/seerge/g-helper) 的 macOS 对应实现。  
> 性能模式、风扇曲线、键盘背光与 Aura 灯效、传感器监控、菜单栏指标、NVIDIA 驱动管理，  
> 用原生 SwiftUI 写成，界面是中性灰白 + 科技蓝的圆角风格。

- 版本：**2.4.28**（build 106）
- 界面：默认 **天选简约**（灰白 / 科技蓝），也支持深色、浅色、跟随系统
- 最低系统：**macOS 13.0**
- 架构：Universal（x86_64 + arm64）
- 许可证：[GPLv3](#许可证)

本地适配机型是 **天选 3 FX507ZM（i7-12700H / RTX 3060）**。硬件控制要配套驱动，详见 [FX507ZM-适配说明.md](FX507ZM-适配说明.md)。

> **本仓库是 [Vela X](https://github.com/Xelon233/Vela-X)（作者 Xelon Jangs / Xelon233）的修改版**，修改自 2026 年 11 月起，按 GPLv3 发布。与原项目作者及华硕均无隶属关系。

---

## 截图预览

<img width="1200" alt="天选简约：概览与实时监测" src="Docs/Images/Tianxuan-Overview.png" />
<img width="1200" alt="深色主题：概览与实时监测" src="Docs/Images/Tianxuan-Overview-Dark.png" />
<img width="160" alt="启动图标" src="Docs/Images/Tianxuan-AppIcon.png" />

概览把 CPU 与 GPU 并排展示，另有性能与键盘灯效的快捷入口，卡片布局可以自己编辑。

## 功能

| 模块 | 说明 |
| --- | --- |
| 性能与风扇 | 性能模式切换；双风扇转速；三档模式（静音 / 平衡 / 增强）；FX507ZM 走 ASUS WMI 固件策略 |
| 键盘背光 | HID 写入（report ID `0x5A`），0–3 档亮度 |
| Aura 灯效 | HID 写入（report ID `0x5D`），12 种灯效模式 |
| 传感器监控 | CPU / GPU 温度、负载、频率、内存、网速、功耗 |
| 菜单栏 | 最多 7 项指标实时拼进菜单栏标题 |
| NVIDIA 驱动 | 检查 / 下载 / 安装 NullMoth 的 macOS NVIDIA 驱动 |
| 适配说明 | FX507ZM 实机修复方案、驱动清单、复现步骤，一键复制完整方案 |
| 命令行 | 同源 CLI：`vela status` / `vela fan ...` / `vela aura ...` |

## 环境要求

- 一台通过 **OpenCore** 运行 macOS 的华硕笔记本。原生 Mac 能编译、能打开界面，但没有华硕硬件控制通道
- macOS 13.0 以上
- 用 `build.sh` 只需要 Command Line Tools；用 Xcode 打开项目则需要完整 Xcode

## 构建

```bash
xcode-select --install      # 没装命令行工具的话先装

./build.sh                  # 编译 → build/天选控制中心.app
./build.sh --dmg            # 编译 + 打包 → dist/天选控制中心-<版本>.dmg
./build.sh x86_64           # 只编指定架构
```

也可以用 Xcode 打开 `天选控制中心.xcodeproj`，选 **天选控制中心** scheme，按 ⌘R 运行。

程序需要「输入监控」权限，**每次重新编译后授权会失效**。想避免就先用自签证书
`./Tools/make_signing_cert.sh`，细节见[技术细节](Docs/技术细节.md#签名细节)。

## 权限

首次运行要在「系统设置 → 隐私与安全性」里授权：

- **输入监控**：键盘背光与 Aura 灯效（HID 写入）
- **辅助功能 / 管理员密码**：驱动安装、风扇控制等需要提权的操作

授权后**要重启 App 才生效**。

## 安全提示

- 程序会直接读写 EC 和 SMC。写错了可能影响风扇、背光和温度保护，**作者不对硬件损坏负责**
- 程序不常驻 root，只在需要时弹一次系统授权
- 这不是华硕官方软件，**可能影响保修**

## 更多文档

- [技术细节](Docs/技术细节.md)：风扇曲线、EC 机型识别、HID 协议、自测方法、目录结构
- [FX507ZM-适配说明.md](FX507ZM-适配说明.md)：本机驱动清单与修复记录
- [ARCHITECTURE.md](ARCHITECTURE.md)：代码分层与责任边界
- [MIGRATION.md](MIGRATION.md)：改名与兼容说明

欢迎 Issue 和 Pull Request。提 Bug 请附 `vela status` 输出、macOS 版本和机型。

## 商标声明

ASUS、天选、ROG / Republic of Gamers 等名称属于各自权利人，这里只用于设备识别。
本项目是社区第三方软件，与华硕没有隶属关系。

## 许可证

[GPLv3](LICENSE) © 2026 XelonJangs（原项目 Vela X）· © 2026 ArdentlyLov（本修改版）

本修改版基于 [Vela X](https://github.com/Xelon233/Vela-X) 修改，采用 **GNU General Public License v3.0**（仅第 3 版）。
你可以自由使用、修改、再分发，但任何分发（含修改版）都必须以相同许可证开源全部源代码，并保留原作者署名。

## 致谢

- [Vela X](https://github.com/Xelon233/Vela-X) — 本项目的直接上游
- [G-Helper](https://github.com/seerge/g-helper) — 原始 Windows 实现与思路来源
- 奥创中心（Armoury Crate）— 设备协议参考
- [NullMoth](https://github.com/nullmoth/nvidia-macos-driver) — macOS NVIDIA 驱动
- angus666888 — EC 灯效修复思路
- [zzzyy678](https://github.com/zzzyy678/SMCNvidiaGPU) — GPU 功耗及显存占用

## 捐赠

本项目是开源修改版，不设捐赠渠道。如果愿意支持，请支持上游 [Vela X](https://github.com/Xelon233/Vela-X) 的作者。
