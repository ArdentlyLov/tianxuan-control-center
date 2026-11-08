import contextlib
import io
import pathlib
import plistlib
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "Tools"))
import test_runtime as runtime


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.efi = self.root / "OC"
        self.efi.mkdir()
        self.bundle = self.root / "VelaAsusWMI.kext"
        (self.bundle / "Contents/MacOS").mkdir(parents=True)
        self.info = {"CFBundleIdentifier": "dev.vela.VelaAsusWMI", "CFBundleExecutable": "VelaAsusWMI", "CFBundleVersion": "1.0.2"}
        (self.bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))
        header = b"\xcf\xfa\xed\xfe" + (0x01000007).to_bytes(4, "little") + bytes(4) + (11).to_bytes(4, "little") + bytes(16)
        (self.bundle / "Contents/MacOS/VelaAsusWMI").write_bytes(header)
        self.app = self.root / "Vela X.app"
        (self.app / "Contents").mkdir(parents=True)
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleVersion": "104"}))
        self.set_enabled(False)

    def tearDown(self):
        self.temp.cleanup()

    def set_enabled(self, enabled):
        (self.efi / "config.plist").write_bytes(plistlib.dumps({"Kernel": {"Add": [
            {"BundlePath": "VelaAsusWMI.kext", "Enabled": enabled}]}}))

    def argv(self, load=False):
        return ["test_runtime", "--efi", str(self.efi), "--bundle", str(self.bundle), "--app", str(self.app)] + (["--load"] if load else [])

    def test_enabled_efi_is_rejected_before_any_command(self):
        self.set_enabled(True)
        with patch.object(runtime.subprocess, "run") as run:
            with self.assertRaises(ValueError): runtime.validate_inputs(self.efi, self.bundle, self.app)
            run.assert_not_called()

    def test_valid_disabled_efi_is_not_modified(self):
        before = (self.efi / "config.plist").read_bytes()
        with patch.object(runtime.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run:
            runtime.validate_inputs(self.efi, self.bundle, self.app)
            self.assertEqual(run.call_count, 2)
        self.assertEqual((self.efi / "config.plist").read_bytes(), before)

    def test_old_bundle_cannot_be_loaded(self):
        self.info["CFBundleVersion"] = "1.0.0"
        (self.bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))
        with patch.object(runtime.subprocess, "run") as run:
            with self.assertRaises(ValueError): runtime.validate_inputs(self.efi, self.bundle, self.app)
            run.assert_not_called()

    def test_default_checks_only_never_loads_or_stages(self):
        with patch.object(sys, "argv", self.argv()), patch.object(runtime.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run, patch.object(runtime.tempfile, "mkdtemp") as stage, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runtime.main(), 0)
            stage.assert_not_called()
            self.assertTrue(all(c.args[0][0] == "/usr/bin/codesign" for c in run.call_args_list))

    def test_loaded_old_module_stops_before_kmutil(self):
        def result(command, **kwargs):
            if command[0] == "/usr/sbin/kextstat":
                return SimpleNamespace(returncode=0, stdout="dev.vela.VelaAsusWMI (1.0.0)", stderr="")
            return SimpleNamespace(returncode=0)
        with patch.object(sys, "argv", self.argv(True)), patch.object(runtime.subprocess, "run", side_effect=result) as run, patch.object(runtime.os, "geteuid", return_value=0), patch.object(runtime.tempfile, "mkdtemp") as stage, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runtime.main(), 1)
            stage.assert_not_called()
            self.assertFalse(any(c.args[0][0] == "/usr/bin/kmutil" for c in run.call_args_list))


if __name__ == "__main__": unittest.main()
