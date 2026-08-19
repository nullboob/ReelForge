import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from reelforge.captions import align, apply_tts_words, cues, cues_overlap, exclusive_cues, safe_area, srt_string
from reelforge.presets import get_preset, max_caption_words
from reelforge.publish import thumbnail_headline, write_pack
from reelforge.script import write
from reelforge.storyboard import build


class CaptionTests(unittest.TestCase):
    def test_packs_to_max_words(self):
        text = "one two three four five six seven eight nine"
        packed = align(text, 9, 4)
        self.assertEqual(len(packed), 3)
        self.assertTrue(all(len(cue["text"].split()) <= 4 for cue in packed))
        self.assertAlmostEqual(packed[0]["start"], 0)
        self.assertAlmostEqual(packed[-1]["start"] + packed[-1]["duration"], 9, delta=0.08)

    def test_viral_hook_is_3_to_6_words(self):
        preset = get_preset("viral-hook")
        self.assertEqual(max_caption_words(preset), 5)
        self.assertEqual(max_caption_words({**preset, "captionStyle": {**preset["captionStyle"], "maxWordsPerCard": 12}}), 6)
        self.assertEqual(max_caption_words({**preset, "captionStyle": {**preset["captionStyle"], "maxWordsPerCard": 2}}), 3)

    def test_safe_area_clears_shorts_chrome(self):
        x, y, w, h = safe_area(1080, 1920)
        self.assertGreaterEqual(y / 1920, 0.17)
        self.assertGreaterEqual((1920 - (y + h)) / 1920, 0.11)
        self.assertLessEqual((x + w) / 1080, 0.83)

    def test_srt_covers_cues(self):
        packed = align("one two three four", 4, 2)
        srt = srt_string(packed)
        self.assertIn("-->", srt)
        self.assertIn("one two", srt)
        self.assertTrue(srt.startswith("1\n"))

    def test_publish_pack_rules(self):
        preset = get_preset("listicle")
        script = write("7 ways to start a faceless channel", "listicle", 45)
        board = build(script, preset, 45)
        pack = write_pack(
            "7 ways to start a faceless channel",
            script,
            board,
            preset,
            {"name": "Night Desk"},
            "Beginner YouTube",
            "short",
            ["Styled card"],
        )
        self.assertLessEqual(len(pack["title"]), 70)
        self.assertEqual(pack["chapters"][0]["timestamp"], "0:00")
        self.assertIn(script["hook"][:20], pack["description"][:150])
        self.assertIn("synthetic", pack["description"].lower())
        line = thumbnail_headline("Stop scrolling. Your morning walk is about to make the usual advice look expensive and tired.")
        self.assertGreaterEqual(len(line.split()), 3)
        self.assertLessEqual(len(line.split()), 6)

    def test_beat_aligned_captions(self):
        preset = get_preset("viral-hook")
        script = write("3 reasons your morning walk beats the gym", "viral-hook")
        board = build(script, preset, 15)
        packed = cues(script, 15, 5, board)
        self.assertTrue(packed)
        for cue in packed:
            self.assertGreaterEqual(cue["start"], -0.001)
            self.assertLessEqual(cue["start"] + cue["duration"], board["duration"] + 0.15)
        self.assertEqual(cues_overlap(packed), [])
        hook = board["beats"][0]
        self.assertEqual(hook["role"], "hook")
        first = packed[0]
        self.assertAlmostEqual(first["start"], hook["start"], delta=0.02)
        self.assertGreaterEqual(first["duration"], min(1.48, hook["duration"] - 0.05))
        self.assertLessEqual(len(first["text"].split()), 6)
        self.assertFalse("." in first["text"].rstrip(".") and first["text"].count(".") > 1)


if __name__ == "__main__":
    unittest.main()
