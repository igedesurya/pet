import importlib.util
import json
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("pet_mcp", Path(__file__).with_name("pet_mcp.py"))
pet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pet)


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.patcher = patch.object(pet, "PET_DIR", self.root)
        self.patcher.start()
        self.add_clip("character", "idle")
        self.add_clip("characters/custom", "running-left")
        self.add_clip("characters/custom", "waiting")
        (self.root / "Resources/characters/custom/pack.json").write_text(json.dumps({"label": "Custom"}))

    def tearDown(self):
        self.patcher.stop()
        self.temp.cleanup()

    def add_clip(self, pack, name):
        directory = self.root / "Resources" / pack / name
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "00.png").write_bytes(b"test frame")

    def test_dynamic_catalog_and_hyphen_names(self):
        pack = pet.find_character("Custom", pet.character_catalog())
        self.assertEqual(pet.resolve_clip(pack, "running left"), "running-left")
        self.add_clip("characters/custom", "new-gesture")
        self.assertIn("new-gesture", pet.visible_poses())

    def test_fallback_aliases_are_not_actual_assets(self):
        pack = pet.find_character("custom", pet.character_catalog())
        self.assertEqual(pet.resolve_clip(pack, "bicara"), "waiting")
        self.assertNotIn("talking", [p["name"] for p in pack["poses"]])
        self.assertIsNone(pet.resolve_clip(pack, "duduk"))

    def test_installed_bundle_takes_precedence(self):
        directory = self.root / "bin/Pet.app/Contents/Resources/character/installed"
        directory.mkdir(parents=True)
        (directory / "00.png").write_bytes(b"frame")
        self.assertEqual([p["name"] for p in pet.character_catalog()[0]["poses"]], ["installed"])

    @patch.object(pet, "is_running", return_value=True)
    @patch.object(pet, "request_pet")
    def test_explicit_wrong_pack_rejects_without_sending(self, request, running):
        result = pet.call_tool("play_pose", {"character": "custom", "pose": "idle"})
        self.assertTrue(result["isError"])
        request.assert_not_called()

    @patch.object(pet, "is_running", return_value=True)
    @patch.object(pet, "request_pet")
    def test_ambiguity_requires_character(self, request, running):
        self.add_clip("character", "waiting")
        request.return_value = {"ok": True, "character": "unknown"}
        result = pet.call_tool("play_pose", {"pose": "waiting"})
        self.assertTrue(result["isError"])
        self.assertIn("Pilih character", result["content"][0]["text"])
        request.assert_called_once_with({"action": "status"})

    @patch.object(pet, "is_running", return_value=True)
    @patch.object(pet, "request_pet", return_value={"ok": True})
    def test_sequence_is_one_atomic_request(self, request, running):
        result = pet.call_tool("play_pose", {"character": "custom", "poses": ["running-left", "bicara"]})
        self.assertNotIn("isError", result)
        request.assert_called_once_with({"action": "play", "character": "custom", "poses": ["running-left", "waiting"]})


class RequestTests(unittest.TestCase):
    def test_timeout_removes_unconsumed_request(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(pet, "PET_HOME", Path(directory)):
            result = pet.request_pet({"action": "status"}, timeout=0.1)
            self.assertFalse(result["ok"])
            self.assertEqual(list((Path(directory) / "command-requests").iterdir()), [])

    def test_acknowledgement_is_read_and_removed(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(pet, "PET_HOME", Path(directory)):
            root = Path(directory)
            def respond():
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    files = list((root / "command-requests").glob("*.json"))
                    if files:
                        pending = files[0]
                        json.loads(pending.read_text())
                        (root / "command-results" / pending.name).write_text(json.dumps({"ok": True, "character": "custom"}))
                        pending.unlink()
                        return
                    time.sleep(0.01)
            thread = threading.Thread(target=respond)
            thread.start()
            result = pet.request_pet({"action": "status"}, timeout=2)
            thread.join()
            self.assertTrue(result["ok"])
            self.assertEqual(list((root / "command-results").iterdir()), [])


if __name__ == "__main__":
    unittest.main()
