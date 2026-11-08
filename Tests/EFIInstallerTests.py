import importlib.util
import pathlib
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

tools = pathlib.Path(__file__).resolve().parents[1] / "Tools"
sys.path.insert(0, str(tools))
import install_opencore as installer


class EFIInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.oc = self.root / "EFI/OC"
        (self.oc / "Kexts").mkdir(parents=True)
        (self.oc / "OpenCore.efi").write_bytes(b"existing-opencore")
        self.original = {"Kernel": {"Add": [{"BundlePath": "VirtualSMC.kext", "Enabled": True}]},
                         "NVRAM": {"Add": {"test": {"boot-args": "actual-live-config"}}}}
        self.before = plistlib.dumps(self.original, fmt=plistlib.FMT_BINARY)
        (self.oc / "config.plist").write_bytes(self.before)
        self.bundle = self.root / "source/VelaAsusWMI.kext"
        (self.bundle / "Contents/MacOS").mkdir(parents=True)
        (self.bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "dev.vela.VelaAsusWMI", "CFBundleExecutable": "VelaAsusWMI"}))
        # Minimal Mach-O header, only used by installer format validation.
        header = b"\xcf\xfa\xed\xfe" + (0x01000007).to_bytes(4, "little") + bytes(4) + (11).to_bytes(4, "little") + bytes(16)
        (self.bundle / "Contents/MacOS/VelaAsusWMI").write_bytes(header)
        self.backups = self.root / "backups"

    def tearDown(self):
        self.temp.cleanup()

    def test_dry_run_writes_nothing(self):
        plan = installer.install_to_oc(self.oc, self.bundle, self.backups)
        self.assertFalse(plan["applied"])
        self.assertEqual((self.oc / "config.plist").read_bytes(), self.before)
        self.assertFalse(self.backups.exists())
        self.assertEqual(list((self.oc / "Kexts").iterdir()), [])

    def test_install_uses_live_config_and_keeps_complete_backup(self):
        plan = installer.install_to_oc(self.oc, self.bundle, self.backups, True)
        after = plistlib.loads((self.oc / "config.plist").read_bytes())
        self.assertEqual(after["Kernel"]["Add"].pop(), installer.patched_config(self.original)["Kernel"]["Add"][-1])
        self.assertEqual(after, self.original)
        backup = pathlib.Path(plan["backup"]) / "OC"
        self.assertEqual((backup / "config.plist").read_bytes(), self.before)
        self.assertEqual((backup / "OpenCore.efi").read_bytes(), b"existing-opencore")
        self.assertTrue(plan["applied"])

    def test_existing_driver_is_backed_up_and_updated(self):
        destination = self.oc / "Kexts/VelaAsusWMI.kext"
        destination.mkdir()
        (destination / "previous.txt").write_text("previous version")
        plan = installer.install_to_oc(self.oc, self.bundle, self.backups, True)
        backup = pathlib.Path(plan["backup"]) / "OC/Kexts/VelaAsusWMI.kext"
        self.assertEqual((backup / "previous.txt").read_text(), "previous version")
        self.assertFalse((destination / "previous.txt").exists())

    def test_commit_failure_restores_original_config_and_driver(self):
        destination = self.oc / "Kexts/VelaAsusWMI.kext"
        destination.mkdir()
        (destination / "previous.txt").write_text("keep me")
        real_write = installer.atomic_write
        def fail_once(path, data):
            if path == self.oc / "config.plist" and data != self.before:
                raise OSError("simulated disk write failure")
            return real_write(path, data)
        with patch.object(installer, "atomic_write", side_effect=fail_once):
            with self.assertRaises(OSError):
                installer.install_to_oc(self.oc, self.bundle, self.backups, True)
        self.assertEqual((self.oc / "config.plist").read_bytes(), self.before)
        self.assertEqual((destination / "previous.txt").read_text(), "keep me")
        self.assertEqual([p.name for p in (self.oc / "Kexts").iterdir()], ["VelaAsusWMI.kext"])

    def test_rejects_bad_driver_before_backup_or_mutation(self):
        (self.bundle / "Contents/MacOS/VelaAsusWMI").write_bytes(b"not-a-kext")
        with self.assertRaises(ValueError):
            installer.install_to_oc(self.oc, self.bundle, self.backups, True)
        self.assertFalse(self.backups.exists())
        self.assertEqual((self.oc / "config.plist").read_bytes(), self.before)

    def test_rejects_invalid_target_and_recursive_backup(self):
        with self.assertRaises(ValueError):
            installer.install_to_oc(self.root, self.bundle, self.backups, True)
        with self.assertRaises(ValueError):
            installer.install_to_oc(self.oc, self.bundle, self.oc / "backups", True)

    def test_selects_partition_by_uuid_even_when_disk_number_changes(self):
        expected = "B0B16B0D-26C8-4CF0-88EE-D891E9A80C43"
        listing = {"AllDisksAndPartitions": [{"Partitions": [
            {"Content": "EFI", "DeviceIdentifier": "disk0s1"},
            {"Content": "EFI", "DeviceIdentifier": "disk3s1"}]}]}
        with patch.object(installer, "diskutil", return_value=plistlib.dumps(listing)), patch.object(installer, "disk_info", side_effect=lambda device: {
            "DeviceIdentifier": device, "DiskUUID": expected if device == "disk3s1" else "11111111-1111-1111-1111-111111111111"}):
            self.assertEqual(installer.find_partition(expected)["DeviceIdentifier"], "disk3s1")


if __name__ == "__main__":
    unittest.main()
