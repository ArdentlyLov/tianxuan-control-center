#!/bin/bash
set -euo pipefail
DRIVER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$DRIVER_ROOT/../.." && pwd)"
DRIVER_BUILD="$PROJECT_ROOT/build/Drivers"
DRIVER_BUNDLE="$DRIVER_BUILD/VelaAsusWMI.kext"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
KERNEL_HEADERS="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
mkdir -p "$DRIVER_BUNDLE/Contents/MacOS"
xcrun clang++ -arch x86_64 -std=c++14 -O2 -mkernel -fapple-kext \
  -fno-exceptions -fno-rtti -fno-builtin -fno-stack-protector \
  -DKERNEL -DKERNEL_PRIVATE -I "$KERNEL_HEADERS" -isysroot "$SDK" \
  -mmacosx-version-min=13.0 -c "$DRIVER_ROOT/VelaAsusWMI.cpp" \
  -o "$DRIVER_BUILD/VelaAsusWMI.o"
xcrun clang++ -arch x86_64 -nostdlib -mkernel \
  -Wl,-kext -Wl,-undefined,dynamic_lookup -Wl,-no_fixup_chains \
  "$DRIVER_BUILD/VelaAsusWMI.o" -o "$DRIVER_BUNDLE/Contents/MacOS/VelaAsusWMI"
cp "$DRIVER_ROOT/Info.plist" "$DRIVER_BUNDLE/Contents/Info.plist"
if xcrun nm -u "$DRIVER_BUNDLE/Contents/MacOS/VelaAsusWMI" | rg 'IOACPIPlatformDevice(9metaClass|10gMetaClass)' >/dev/null; then
  echo "ERROR: kernel extension references an unavailable ACPI metaclass symbol" >&2
  exit 1
fi
plutil -lint "$DRIVER_BUNDLE/Contents/Info.plist"
echo "Built: $DRIVER_BUNDLE"
