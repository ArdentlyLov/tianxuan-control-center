"""Regression checks for the boot-loop defects; does not load a kernel extension."""
import pathlib
import plistlib
import re
import subprocess
import unittest

root = pathlib.Path(__file__).resolve().parents[1]
driver = root / "Drivers/VelaAsusWMI"
binary = root / "build/Drivers/VelaAsusWMI.kext/Contents/MacOS/VelaAsusWMI"


def method_body(source, marker):
    begin = source.index("{", source.index(marker))
    depth = 1
    end = begin + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[begin + 1:end - 1]


class DriverBuildTests(unittest.TestCase):
    def test_binary_has_no_unexported_acpi_metaclass_reference(self):
        undefined = subprocess.check_output(["xcrun", "nm", "-u", str(binary)], text=True)
        self.assertNotIn("IOACPIPlatformDevice9metaClass", undefined)
        self.assertNotIn("IOACPIPlatformDevice10gMetaClass", undefined)

    def test_module_is_x86_64_kext_and_has_entry_points(self):
        data = binary.read_bytes()
        self.assertEqual(data[:4], b"\xcf\xfa\xed\xfe")
        self.assertEqual(int.from_bytes(data[4:8], "little"), 0x01000007)
        self.assertEqual(int.from_bytes(data[12:16], "little"), 11)
        symbols = subprocess.check_output(["xcrun", "nm", str(binary)], text=True)
        for name in ["_kmod_info", "_VelaAsusWMI_start", "_VelaAsusWMI_stop"]:
            self.assertIn(name, symbols)
        info = plistlib.loads((binary.parents[1] / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleVersion"], "1.0.2")
        self.assertNotIn("com.apple.driver.AppleACPIPlatform", info["OSBundleLibraries"])

    def test_start_and_capability_publication_do_not_probe_firmware(self):
        source = (driver / "VelaAsusWMI.cpp").read_text()
        for marker in ["bool start(IOService *provider)", "void publishCapabilities()"]:
            body = method_body(source, marker)
            calls = set(re.findall(r"\b([a-zA-Z_][a-zA-Z_0-9]*)\s*\(", body))
            self.assertTrue(calls.isdisjoint({"evaluate", "evaluateObject", "findManagementMethod",
                "getStatus", "getCurve", "present", "probeFirmware"}), calls)

    def test_probe_is_explicit_and_old_driver_is_not_auto_enabled(self):
        source = (driver / "VelaAsusWMI.cpp").read_text()
        self.assertIn("if (selector == 4)", source)
        self.assertIn("if (!driver->isFirmwareProbed()) return kIOReturnNotReady", source)
        self.assertIn('"Enabled": False', (root / "Tools/prepare_opencore.py").read_text())


if __name__ == "__main__":
    unittest.main()
