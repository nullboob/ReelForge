import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from reelforge import caption_ass, caption_png, caption_styles
from reelforge.footage import specific_query


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


if __name__ == "__main__":
    unittest.main()
