import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from reelforge.hooks import is_forbidden_open
from reelforge.niche import warning_for
from reelforge.presets import load_presets
from reelforge.script import write
from reelforge.storyboard import StoryboardError, build


class StoryboardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.presets = {p["id"]: p for p in load_presets()}

    def test_first_beat_is_hook_and_holds_1_5s(self):
        preset = self.presets["viral-hook"]
        script = write("3 reasons your morning walk beats the gym", "viral-hook")
        board = build(script, preset, 15)
        self.assertEqual(board["beats"][0]["role"], "hook")
        self.assertGreaterEqual(board["beats"][0]["duration"], 1.48)
        self.assertAlmostEqual(board["duration"], 15, delta=0.08)

    def test_greeting_open_fails_builder(self):
        preset = self.presets["viral-hook"]
        script = {"hook": "Welcome back to the channel.", "body": ["A later beat."], "cta": "Subscribe.", "source": "template"}
        with self.assertRaises(StoryboardError):
            build(script, preset, 15)

    def test_empty_script_gets_hook_fallback(self):
        preset = self.presets["viral-hook"]
        board = build({"hook": "", "body": [], "cta": "", "source": "template"}, preset, 15)
        self.assertEqual(board["beats"][0]["role"], "hook")
        self.assertFalse(is_forbidden_open(board["beats"][0]["text"]))

    def test_forbidden_opens(self):
        self.assertTrue(is_forbidden_open("Welcome back to the channel"))
        self.assertTrue(is_forbidden_open("In this video we discuss walking"))
        self.assertFalse(is_forbidden_open("Stop scrolling. Your walk wins."))

    def test_niche_guard(self):
        self.assertIsNotNone(warning_for("as a doctor I recommend this supplement"))
        self.assertIsNone(warning_for("3 reasons your morning walk beats the gym"))

    def test_fourteen_presets(self):
        self.assertEqual(len(self.presets), 14)
        self.assertIn("podcast-clip", self.presets)
        self.assertIn("news-roundup", self.presets)


if __name__ == "__main__":
    unittest.main()
