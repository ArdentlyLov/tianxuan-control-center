# 天选控制中心改名与迁移

版本 2.4.28（build 106）。中文名称「天选控制中心」，英文名称「Tianxuan Control Center」。

构建产物为 `build/天选控制中心.app`，Xcode 工程与共享方案为 `天选控制中心`。命令行入口新增 `build/tianxuan`，原 `build/vela` 和 `build/asuscontrol` 继续可用。

Bundle ID `dev.vela.mac`、可执行文件名 `AsusControl`、偏好键和驱动标识保持兼容。现有偏好继续使用原存储位置。

本机安装到 `/Applications/天选控制中心.app`，原 `/Applications/Vela X.app` 用符号链接指向新应用。已有免密授权若绑定旧路径，应用只在旧路径解析到当前实际可执行文件时复用它。登录启动配置在启动时更新为新应用位置。

应用备份与重构前源码保存在项目 `build/` 下。代码签名方式沿用当前构建配置；若使用 ad-hoc 签名，输入监控权限可能需要重新授权，保留 Bundle ID 本身不能保证 TCC 授权稳定。

硬件接口和驱动源代码保持独立，构建不安装或加载内核驱动，不修改启动 EFI。目录说明见 `ARCHITECTURE.md`。
