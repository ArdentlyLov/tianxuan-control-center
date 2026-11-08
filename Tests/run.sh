#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BUILD="$PROJECT_ROOT/build/Tests"
mkdir -p "$TEST_BUILD/ModuleCache"
xcrun swiftc -swift-version 5 -module-cache-path "$TEST_BUILD/ModuleCache" \
  "$PROJECT_ROOT/Sources/Core/Models/HardwareIdentity.swift" "$PROJECT_ROOT/Sources/Hardware/ASUS/ECProfiles.swift" \
  "$PROJECT_ROOT/Sources/Core/Models/ModelCatalog.swift" "$PROJECT_ROOT/Sources/Hardware/ASUS/ASUSWMIProtocol.swift" \
  "$PROJECT_ROOT/Tests/HardwareTests.swift" -o "$TEST_BUILD/HardwareTests"
"$TEST_BUILD/HardwareTests"
xcrun clang++ -std=c++14 "$PROJECT_ROOT/Tests/WMIArgumentsTests.cpp" -o "$TEST_BUILD/WMIArgumentsTests"
"$TEST_BUILD/WMIArgumentsTests"
xcrun swiftc -swift-version 5 -module-cache-path "$TEST_BUILD/ModuleCache" \
  "$PROJECT_ROOT/Sources/Core/Control/FanPresetApplication.swift" "$PROJECT_ROOT/Tests/FanPresetApplicationTests.swift" \
  -o "$TEST_BUILD/FanPresetApplicationTests"
"$TEST_BUILD/FanPresetApplicationTests"
xcrun swiftc -swift-version 5 -module-cache-path "$TEST_BUILD/ModuleCache" \
  "$PROJECT_ROOT/Sources/Core/Control/ThermalControl.swift" "$PROJECT_ROOT/Tests/ThermalControlTests.swift" \
  -o "$TEST_BUILD/ThermalControlTests" -framework Combine
"$TEST_BUILD/ThermalControlTests"
xcrun clang -dynamiclib "$PROJECT_ROOT/Tests/IntelPowerMock.c" -o "$TEST_BUILD/IntelPowerMock.dylib"
xcrun swiftc -swift-version 5 -module-cache-path "$TEST_BUILD/ModuleCache" \
  "$PROJECT_ROOT/Sources/Hardware/Intel/IntelPowerProbe.swift" "$PROJECT_ROOT/Tests/IntelPowerTests.swift" \
  -o "$TEST_BUILD/IntelPowerTests"
"$TEST_BUILD/IntelPowerTests" "$TEST_BUILD/IntelPowerMock.dylib"
xcrun swiftc -swift-version 5 -module-cache-path "$TEST_BUILD/ModuleCache" \
  "$PROJECT_ROOT/Sources/Core/Monitoring/TelemetryParsing.swift" \
  "$PROJECT_ROOT/Sources/Hardware/NVIDIA/NvidiaRUSD.swift" "$PROJECT_ROOT/Tests/TelemetryTests.swift" \
  -o "$TEST_BUILD/TelemetryTests"
"$TEST_BUILD/TelemetryTests"
