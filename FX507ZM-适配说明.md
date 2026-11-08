# 天选3 FX507ZM 适配记录

当前应用 2.4.28 build 106。以下记录保留旧驱动 1.0.2 的修正经过。旧版 1.0.0 在此电脑上造成了启动循环，已停用。
实际 EFI 的 VelaAsusWMI.kext 应继续保持 Enabled=false。当前不是可直接安装到启动 EFI 的版本。

启动日志显示旧驱动的 IOACPIPlatformDevice::metaClass 被解析为地址零。
1.0.2 使用运行时按类名核对类型，编译后检查不存在对该数据符号的引用。
本机实际 WMNB 会无条件创建 IIA0..IIA4，所有请求现在都提供 20 字节。
本机曲线方法返回 32 字节，前 16 字节是有效曲线数据，驱动接受其固件填充。

1.0.1 的实机临时加载在依赖检查阶段被拒绝（退出码 71），没有进入驱动启动。
本机 AppleACPIPlatform 的版本和最低兼容版本均为 6.1，旧声明的 1.0.0 不兼容。
1.0.2 移除这项不需要的链接依赖：二进制没有直接引用 ACPI 符号，ACPI 调用经已匹配对象的虚方法执行。
保留实际需要的 IOKit、libkern、mach 内核依赖。此修正仍需实机验证加载。

驱动启动不执行任何固件方法，包括 _WDG。应用连接时只读取服务属性。
手动点击「读取固件接口」或执行 `AsusControl wmi probe` 后才进行只读固件探测。
旧临时验证版本曾停用自动下发。当前应用已按实际能力恢复控制，增强模式、CPU 温度、频率与功耗已在本机运行验证；当前运行驱动报告 1.0.3。本次应用更新不更改或重新加载该驱动。

## 构建与检查

在 Xcode 打开 `天选控制中心.xcodeproj`，选择「天选控制中心」构建。
该工程会编译驱动，不会加载驱动。

```bash
bash Tests/run.sh
bash Drivers/VelaAsusWMI/build.sh
python3 Tests/DriverBuildTests.py
python3 Tests/EFIConfigTests.py
python3 Tests/EFIInstallerTests.py
python3 Tests/RuntimeTests.py
```

检查不能代替内核实机加载。没有新的内核 panic 记录可以证明全部启动问题已经消失。

## 临时验证

交付包中的「临时加载检查.command」先核对实际 EFI 仍关闭驱动，核对二进制和签名，
然后在已进入的系统里分别执行 start-only 和 match-only。它不修改 EFI、不写入 /Library/Extensions。
临时加载仍可能导致一次系统重启，执行前应保存工作。
加载成功后先确认系统稳定，再手动执行只读探测。只读能力验证通过后再逐项测试平衡模式、背光和单区 RGB。
未公开的能力保持不可用。只有完成实机验证后才考虑持久加载。

## 协议来源

- 本机实际启动 ACPI 的 WMNB 和曲线方法（仅本地诊断，完整固件不随源码分发）。
- Linux ASUS WMI：https://github.com/torvalds/linux/blob/master/drivers/platform/x86/asus-wmi.c
- G-Helper TUF 接口：https://github.com/seerge/g-helper/blob/main/app/AsusACPI.cs
- 原项目：https://github.com/Xelon233/Vela-X

保留原作者署名和 GPLv3 许可。新增代码按 GPLv3 或后续版本提供。
