import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from reelforge import caption_ass, caption_png, caption_styles
from reelforge.captions import apply_tts_words, cues, cues_overlap, exclusive_cues
from reelforge.cards import render_card
from reelforge.footage import specific_query
from reelforge.presets import get_preset
from reelforge.renderer import cover_vf
from reelforge.script import write
from reelforge.storyboard import build


class CaptionEngineTests(unittest.TestCase):
    def test_catalog_has_thirty_required_styles(self):
        styles = caption_styles.all_styles()
        ids = {item["id"] for item in styles}
        self.assertGreaterEqual(len(styles), 30)
        for required in caption_styles.REQUIRED_IDS:
            self.assertIn(required, ids)
        self.assertEqual(caption_styles.default_for_preset("viral-hook"), "dynamic-minimal")

    def test_ass_karaoke_emits_k_tags(self):
        style = caption_styles.style_by_id("dynamic-minimal")
        cues = [{
            "start": 0.0,
            "duration": 1.2,
            "text": "Stop scrolling now",
            "words": [
                {"word": "Stop", "start": 0.0, "duration": 0.3},
                {"word": "scrolling", "start": 0.3, "duration": 0.5},
                {"word": "now", "start": 0.8, "duration": 0.4},
            ],
        }]
        ass = caption_ass.build_ass(cues, style, 1080, 1920, "Montserrat ExtraBold")
        self.assertIn(r"\k", ass)
        self.assertIn("Dialogue:", ass)
        self.assertNotIn("Arial", ass)

    def test_png_writes_nonempty_rgba(self):
        style = caption_styles.style_by_id("sunset-fill")
        cue = {"start": 0, "duration": 1, "text": "Morning walk", "words": [{"word": "Morning", "duration": 0.4}, {"word": "walk", "duration": 0.4}]}
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "cap.png"
            caption_png.render_cue_png(cue, style, dest, (1080, 1920), caption_styles.font_path(style))
            self.assertGreater(dest.stat().st_size, 200)
            from PIL import Image
            with Image.open(dest) as image:
                self.assertEqual(image.mode, "RGBA")
                self.assertGreater(max(image.size), 100)

    def test_stock_query_uses_nouns(self):
        rewritten = specific_query("office handshake")
        self.assertIn("handheld", rewritten)
        self.assertNotEqual(rewritten, "office handshake")

    def test_burned_cues_do_not_overlap(self):
        overlapping = [
            {"id": "a", "text": "Stop scrolling.", "start": 0.0, "duration": 2.0, "words": []},
            {"id": "b", "text": "Morning walk beats the", "start": 0.4, "duration": 1.8, "words": []},
        ]
        self.assertTrue(cues_overlap(overlapping))
        fixed = exclusive_cues(overlapping)
        self.assertEqual(cues_overlap(fixed), [])
        self.assertLessEqual(fixed[0]["start"] + fixed[0]["duration"], fixed[1]["start"] + 1e-6)

        preset = get_preset("viral-hook")
        script = write("3 reasons your morning walk beats the gym", "viral-hook")
        board = build(script, preset, 15)
        packed = cues(script, 15, 5, board)
        self.assertEqual(cues_overlap(packed), [])
        remapped = apply_tts_words(packed, [
            {"word": "Stop", "start": 0.0, "duration": 0.9},
            {"word": "scrolling.", "start": 0.2, "duration": 1.4},
            {"word": "Morning", "start": 0.5, "duration": 1.1},
        ])
        self.assertEqual(cues_overlap(remapped), [])

        style = caption_styles.style_by_id("dynamic-minimal")
        ass = caption_ass.build_ass(overlapping, style, 1080, 1920, "Montserrat ExtraBold")
        windows = caption_ass.dialogue_windows(ass)
        self.assertGreaterEqual(len(windows), 2)
        for index, left in enumerate(windows):
            for right in windows[index + 1 :]:
                self.assertFalse(left[0] < right[1] - 1e-4 and right[0] < left[1] - 1e-4)

    def test_hook_is_single_replacing_card(self):
        preset = get_preset("viral-hook")
        script = {
            "hook": "Stop scrolling. Morning walk beats the gym.",
            "body": ["Reason one is free daylight.", "Reason two is a quieter head."],
            "cta": "Follow for the next walk.",
            "source": "user",
        }
        board = build(script, preset, 15)
        packed = cues(script, 15, 5, board)
        first = packed[0]
        self.assertIn("Stop", first["text"])
        self.assertNotIn("Morning", first["text"])
        self.assertGreaterEqual(first["duration"], 1.48)
        if len(packed) > 1:
            self.assertGreaterEqual(packed[1]["start"], first["start"] + first["duration"] - 1e-4)

    def test_card_fills_export_pixels(self):
        preset = get_preset("viral-hook")
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "card.png"
            render_card("Stop scrolling. Morning walk beats the gym.", dest, (1080, 1920), preset)
            from PIL import Image
            with Image.open(dest) as image:
                self.assertEqual(image.size, (1080, 1920))
                top = image.getpixel((540, 8))
                mid = image.getpixel((540, 960))
                self.assertNotEqual(top, (0, 0, 0))
                self.assertNotEqual(mid, (0, 0, 0))
        vf = cover_vf(1080, 1920, ken_burns=True, duration=1.5)
        self.assertIn("crop=1080:1920", vf)
        self.assertIn("setsar=1", vf)
        self.assertNotIn("pad=", vf)


if __name__ == "__main__":
    unittest.main()
