import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / "Tools" / "prepare_opencore.py"
spec = importlib.util.spec_from_file_location("prepare_opencore", path)
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)

class EFIConfigTests(unittest.TestCase):
    def original(self):
        return {"Kernel": {"Add": [{"BundlePath": "VirtualSMC.kext", "Enabled": True}],
                           "Quirks": {"DisableLinkeditJettison": True}},
                "NVRAM": {"Add": {"example": {"boot-args": "unchanged"}}},
                "PlatformInfo": {"Generic": {"SystemProductName": "MacBookPro16,2"}}}
    def test_preserves_every_other_setting(self):
        original = self.original()
        result = patch.patched_config(original)
        self.assertEqual(result["Kernel"]["Add"].pop(), patch.ENTRY)
        self.assertEqual(result, original)
    def test_does_not_modify_input(self):
        original = self.original()
        patch.patched_config(original)
        self.assertEqual(original, self.original())
    def test_idempotent(self):
        first = patch.patched_config(self.original())
        self.assertEqual(patch.patched_config(first), first)
    def test_keeps_existing_driver_disabled(self):
        original = self.original()
        original["Kernel"]["Add"].append({"BundlePath": patch.BUNDLE, "Enabled": False})
        result = patch.patched_config(original)
        self.assertEqual(len(result["Kernel"]["Add"]), 2)
        self.assertFalse(result["Kernel"]["Add"][-1]["Enabled"])
    def test_rejects_duplicate_or_invalid_config(self):
        for data in [{}, {"Kernel": {"Add": "invalid"}},
                     {"Kernel": {"Add": [{"BundlePath": patch.BUNDLE}, {"BundlePath": patch.BUNDLE}]}}]:
            with self.assertRaises(ValueError): patch.patched_config(data)

if __name__ == "__main__": unittest.main()
