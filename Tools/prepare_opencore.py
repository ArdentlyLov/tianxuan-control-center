#!/usr/bin/env python3
"""Prepare a minimal OpenCore change; never overwrite the input configuration."""
import argparse
import copy
import plistlib
from pathlib import Path

BUNDLE = "VelaAsusWMI.kext"
ENTRY = {
    "Arch": "x86_64", "BundlePath": BUNDLE,
    "Comment": "天选控制中心 ASUS WMI / FX507ZM (disabled: pending runtime verification)", "Enabled": False,
    "ExecutablePath": "Contents/MacOS/VelaAsusWMI",
    "MaxKernel": "", "MinKernel": "22.0.0", "PlistPath": "Contents/Info.plist",
}

def patched_config(original):
    if not isinstance(original, dict) or not isinstance(original.get("Kernel"), dict):
        raise ValueError("不是有效的 OpenCore 配置：缺少 Kernel 字典")
    entries = original["Kernel"].get("Add")
    if not isinstance(entries, list) or not all(isinstance(entry, dict) for entry in entries):
        raise ValueError("不是有效的 OpenCore 配置：Kernel/Add 必须是驱动列表")
    result = copy.deepcopy(original)
    matching = [i for i, entry in enumerate(entries)
                if str(entry.get("BundlePath", "")).casefold() == BUNDLE.casefold()]
    if len(matching) > 1:
        raise ValueError("配置中有重复的 VelaAsusWMI 驱动项，请先核对")
    if matching:
        result["Kernel"]["Add"][matching[0]].update(ENTRY)
    else:
        result["Kernel"]["Add"].append(copy.deepcopy(ENTRY))
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.input.resolve() == args.output.resolve():
        parser.error("输出不能覆盖输入配置")
    with args.input.open("rb") as handle:
        result = patched_config(plistlib.load(handle))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as handle:
        plistlib.dump(result, handle, sort_keys=False)
    print("已准备配置：仅新增或更新 Kernel/Add 中的 VelaAsusWMI 项")

if __name__ == "__main__":
    main()
