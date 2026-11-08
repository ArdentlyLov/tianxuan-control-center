#!/usr/bin/env python3
"""Validate first, then explicitly load the candidate into a running system only."""
import argparse
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile

from install_opencore import validate_bundle


def validate_inputs(efi, bundle, app):
    config = plistlib.loads((efi / "config.plist").read_bytes())
    entries = config.get("Kernel", {}).get("Add")
    if not isinstance(entries, list):
        raise ValueError("无法核对实际 EFI 的加载项")
    for entry in entries:
        if str(entry.get("BundlePath", "")).casefold() == "velaasuswmi.kext" and entry.get("Enabled"):
            raise ValueError("实际 EFI 的 VelaAsusWMI 仍然开启，先保持关闭才能临时验证")
    validate_bundle(bundle)
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleVersion") != "1.0.2":
        raise ValueError("只能临时验证修正版 1.0.2")
    app_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if app_info.get("CFBundleVersion") != "104":
        raise ValueError("必须使用配套应用 build 104")
    for path in [bundle, app]:
        result = subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(path)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            raise ValueError("签名完整性校验失败：" + str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--efi", type=pathlib.Path, default=pathlib.Path("/Volumes/SYSTEM/EFI/OC"))
    parser.add_argument("--bundle", type=pathlib.Path, required=True)
    parser.add_argument("--app", type=pathlib.Path, required=True)
    parser.add_argument("--load", action="store_true", help="显式临时加载；默认只检查")
    args = parser.parse_args()
    try:
        validate_inputs(args.efi, args.bundle, args.app)
        print("检查通过：实际 EFI 保持关闭，驱动 1.0.2 和应用 build 104 完整。", flush=True)
        if not args.load:
            print("只检查，未加载驱动、未修改 EFI。")
            return 0
        if os.geteuid() != 0:
            raise RuntimeError("临时加载需要系统管理员权限")
        loaded = subprocess.run(["/usr/sbin/kextstat", "-l", "-b", "dev.vela.VelaAsusWMI"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if loaded.returncode:
            raise RuntimeError("无法核对已加载的内核模块，停止临时加载：" + loaded.stderr.strip())
        if "dev.vela.VelaAsusWMI" in loaded.stdout and "(1.0.2)" not in loaded.stdout:
            raise RuntimeError("内核已有其他版本的 VelaAsusWMI 模块，停止临时加载")
        staged = pathlib.Path(tempfile.mkdtemp(prefix="VelaAsusWMI-runtime-", dir="/private/tmp"))
        target = staged / "VelaAsusWMI.kext"
        shutil.copytree(args.bundle, target)
        for path in [staged, target, *target.rglob("*")]:
            os.chown(path, 0, 0)
        for style in ["start-only", "match-only"]:
            print("临时加载阶段：" + style + "（不读取固件，不修改 EFI）", flush=True)
            result = subprocess.run(["/usr/bin/kmutil", "load", "--bundle-path", str(target),
                                     "--load-style", style])
            if result.returncode:
                raise RuntimeError("系统拒绝临时加载，阶段 " + style + "，退出码 " + str(result.returncode))
        executable = args.app / "Contents/MacOS/AsusControl"
        result = subprocess.run([str(executable), "wmi"])
        if result.returncode:
            raise RuntimeError("临时加载后仍未发现驱动服务")
        print("驱动服务已连接，尚未探测固件。请先确认系统稳定，再在应用中手动读取固件接口。", flush=True)
        print("实际 EFI 未改变；未写入 /Library/Extensions；未执行重启。")
        return 0
    except Exception as error:
        print("临时验证未完成：" + str(error), flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
