#!/usr/bin/env python3
"""Install only the Vela WMI kext, using the current EFI config and a full OC backup."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from datetime import datetime
from uuid import UUID, uuid4

from prepare_opencore import BUNDLE, patched_config


def digest(data):
    return hashlib.sha256(data).hexdigest()


def diskutil(*arguments):
    result = subprocess.run(["/usr/sbin/diskutil", *arguments],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        message = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError("无法访问 EFI 分区：" + message)
    return result.stdout


def disk_info(device):
    return plistlib.loads(diskutil("info", "-plist", device))


def find_partition(partition_uuid):
    expected = str(UUID(partition_uuid)).upper()
    listing = plistlib.loads(diskutil("list", "-plist"))
    candidates = []

    def visit(value):
        if isinstance(value, dict):
            if value.get("Content") == "EFI" and value.get("DeviceIdentifier"):
                candidates.append(value["DeviceIdentifier"])
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(listing)
    matches = []
    for device in sorted(set(candidates)):
        info = disk_info(device)
        if str(info.get("DiskUUID", "")).upper() == expected:
            matches.append(info)
    if len(matches) != 1:
        raise RuntimeError("没有找到唯一匹配的启动 EFI 分区；不会改动其他磁盘")
    return matches[0]


def validate_bundle(bundle):
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    executable = bundle / "Contents/MacOS/VelaAsusWMI"
    data = executable.read_bytes()
    if info.get("CFBundleVersion") == "1.0.0" or digest(data) == "0bbd8f28ead9266d4e578d3fc3f4587c41f45bd13eafee4de762b9cdd279a0d8":
        raise ValueError("旧版 VelaAsusWMI 1.0.0 造成过启动循环，禁止再次安装或加载")
    if info.get("CFBundleIdentifier") != "dev.vela.VelaAsusWMI" or info.get("CFBundleExecutable") != "VelaAsusWMI":
        raise ValueError("驱动标识不正确")
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe" or int.from_bytes(data[4:8], "little") != 0x01000007 or int.from_bytes(data[12:16], "little") != 11:
        raise ValueError("驱动必须是 x86_64 内核扩展")
    if any(path.is_symlink() for path in [bundle, *bundle.rglob("*")]):
        raise ValueError("驱动包含有符号链接")
    return digest(data)


def atomic_write(path, data):
    descriptor, temporary = tempfile.mkstemp(prefix=".VelaAsusWMI-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def install_to_oc(oc, bundle, backup_root, apply=False):
    oc, bundle, backup_root = Path(oc), Path(bundle), Path(backup_root)
    config, kexts = oc / "config.plist", oc / "Kexts"
    if any(path.is_symlink() for path in [oc, config, kexts, oc / "OpenCore.efi"]):
        raise ValueError("EFI 关键路径不能是符号链接")
    if not (oc / "OpenCore.efi").is_file() or not config.is_file() or not kexts.is_dir():
        raise ValueError("目标缺少 OC/config.plist、OC/Kexts 或 OpenCore.efi")
    original_bytes = config.read_bytes()
    original = plistlib.loads(original_bytes)
    patched = patched_config(original)
    planned_bytes = plistlib.dumps(patched, sort_keys=False)
    bundle_hash = validate_bundle(bundle)
    destination = kexts / BUNDLE
    if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
        raise ValueError("已有驱动路径不是普通文件夹")
    if backup_root.resolve().is_relative_to(oc.resolve()):
        raise ValueError("备份目录不能放在 OC 内部")
    plan = {"oc": str(oc.resolve()), "config_sha256_before": digest(original_bytes),
            "config_sha256_after": digest(planned_bytes), "driver_sha256": bundle_hash,
            "previous_driver": destination.exists(), "applied": False}
    if not apply:
        return plan

    # Backup completes before the first change to the boot files.
    backup_root.mkdir(parents=True, exist_ok=True)
    backup = backup_root / (datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid4().hex[:8])
    backup.mkdir()
    shutil.copytree(oc, backup / "OC", symlinks=True)
    if (backup / "OC/config.plist").read_bytes() != original_bytes or config.read_bytes() != original_bytes:
        raise RuntimeError("备份期间配置发生变化，已停止安装")
    plan["backup"] = str(backup.resolve())
    atomic_write(backup / "installation.json", json.dumps(plan, ensure_ascii=False, indent=2).encode())
    suffix = uuid4().hex
    staging = kexts / (".VelaAsusWMI-stage-" + suffix)
    previous = kexts / (".VelaAsusWMI-previous-" + suffix)
    changed = False
    try:
        shutil.copytree(bundle, staging)
        if validate_bundle(staging) != bundle_hash:
            raise RuntimeError("驱动复制校验失败")
        if config.read_bytes() != original_bytes:
            raise RuntimeError("实际 EFI 配置发生变化，已停止安装")
        if destination.exists():
            os.replace(destination, previous)
            changed = True
        os.replace(staging, destination)
        changed = True
        atomic_write(config, planned_bytes)
        if config.read_bytes() != planned_bytes or validate_bundle(destination) != bundle_hash:
            raise RuntimeError("安装后的配置或驱动校验失败")
    except Exception as error:
        if changed:
            try:
                atomic_write(config, original_bytes)
                if destination.exists():
                    shutil.rmtree(destination)
                if previous.exists():
                    os.replace(previous, destination)
            except Exception as rollback_error:
                raise RuntimeError("安装失败，自动恢复也失败；请使用备份 " + str(backup) + "。恢复错误：" + str(rollback_error)) from error
        raise
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    plan["applied"] = True
    # After a successful commit, cleanup trouble must not undo a valid installation.
    if previous.exists():
        shutil.rmtree(previous)
    atomic_write(backup / "installation.json", json.dumps(plan, ensure_ascii=False, indent=2).encode())
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--partition-uuid", required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--backup-root", type=Path, required=True)
    parser.add_argument("--install", action="store_true", help="写入 EFI；默认只检查")
    args = parser.parse_args()
    try:
        validate_bundle(args.bundle)
        if args.install:
            raise RuntimeError("EFI 安装已停用：旧版驱动造成过循环重启。仅允许进入系统后临时验证新驱动，保持 EFI 加载项关闭")
        if args.install and os.geteuid() != 0:
            raise RuntimeError("安装到启动 EFI 需要系统管理员权限")
        info = find_partition(args.partition_uuid)
        device = info["DeviceIdentifier"]
        if not info.get("MountPoint"):
            if not args.install:
                print("已找到匹配的 EFI 分区：" + device + "，尚未挂载；未修改文件")
                return 0
            diskutil("mount", device)
            info = disk_info(device)
        if str(info.get("DiskUUID", "")).upper() != str(UUID(args.partition_uuid)).upper() or not info.get("MountPoint"):
            raise RuntimeError("挂载后的分区身份不符；已停止")
        oc = Path(info["MountPoint"]) / "EFI/OC"
        plan = install_to_oc(oc, args.bundle, args.backup_root, apply=args.install)
        if args.install:
            print("已备份实际 OC 文件夹：" + plan["backup"])
            print("已安装 VelaAsusWMI：只更新这一驱动及其加载项，其他配置保持原值。")
            print("请自行重启，再打开 天选控制中心 验证；安装工具不会自动重启。")
        else:
            print("检查通过：" + str(oc) + "；未修改 EFI")
        return 0
    except Exception as error:
        print("安装未完成：" + str(error))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
