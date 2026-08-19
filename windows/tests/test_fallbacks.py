import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from reelforge import errors, footage, speech


class FootageFallbackTests(unittest.TestCase):
    def test_pexels_hit_skips_infer(self):
        beats = [{"id": "b0", "text": "morning walk outside", "start": 0, "duration": 3, "unsplashQuery": "morning walk"}]
        called = {"video": 0, "image": 0}

        def fake_search(*_args, **_kwargs):
            return {"id": 9, "url": "https://example.com/clip.mp4", "photographer": "Ada"}

        def fake_download(_url, dest):
            Path(dest).write_bytes(b"mp4" * 200)
            return True

        def fake_video(*_args, **_kwargs):
            called["video"] += 1
            return False

        def fake_image(*_args, **_kwargs):
            called["image"] += 1
            return False

        with tempfile.TemporaryDirectory() as tmp, \
                patch("reelforge.footage.search_pexels", fake_search), \
                patch("reelforge.footage.download", fake_download), \
                patch("reelforge.infer.generate_video", fake_video), \
                patch("reelforge.infer.generate_image", fake_image):
            assignments, ledger, warnings, cards_only = footage.gather(
                beats, {"aiImageStyleSuffix": "photoreal"}, "9:16", Path(tmp),
                pexels_key="pexels-key",
                use_pexels=True,
                channel_name="test",
                local_mode="stock-first",
                use_local_models=True,
            )
        self.assertFalse(cards_only)
        self.assertEqual(assignments["b0"]["source"], "pexels")
        self.assertEqual(called["video"], 0)
        self.assertEqual(called["image"], 0)
        self.assertTrue(any(entry["credit"] == "Ada / Pexels" for entry in ledger))

    def test_offline_paints_not_cards_only(self):
        beats = [
            {"id": "b0", "text": "morning walk", "start": 0, "duration": 3, "unsplashQuery": "walk"},
            {"id": "b1", "text": "second beat", "start": 3, "duration": 3, "unsplashQuery": "path"},
        ]
        with tempfile.TemporaryDirectory() as tmp, \
                patch("reelforge.infer.generate_video", return_value=False), \
                patch("reelforge.infer.generate_image", return_value=False):
            assignments, ledger, warnings, cards_only = footage.gather(
                beats, {"aiImageStyleSuffix": "photoreal"}, "9:16", Path(tmp),
                pexels_key=None,
                use_pexels=True,
                channel_name="test",
                pixabay_key=None,
                use_pixabay=True,
                use_local_models=True,
                local_mode="local-fast",
            )
        self.assertFalse(cards_only)
        self.assertTrue(all(item["source"] == "painted" for item in assignments.values()))
        self.assertTrue(any("painted" in item.lower() for item in warnings))
        self.assertTrue(any(entry.get("credit") == "Painted art" for entry in ledger))

    def test_paint_fail_is_cards_only(self):
        beats = [
            {"id": "b0", "text": "morning walk", "start": 0, "duration": 3, "unsplashQuery": "walk"},
            {"id": "b1", "text": "second beat", "start": 3, "duration": 3, "unsplashQuery": "path"},
        ]
        with tempfile.TemporaryDirectory() as tmp, \
                patch("reelforge.infer.generate_video", return_value=False), \
                patch("reelforge.infer.generate_image", return_value=False), \
                patch("reelforge.footage.render_painted", side_effect=RuntimeError("paint failed")):
            assignments, ledger, warnings, cards_only = footage.gather(
                beats, {"aiImageStyleSuffix": "photoreal"}, "9:16", Path(tmp),
                pexels_key=None,
                use_pexels=True,
                channel_name="test",
                use_local_models=True,
                local_mode="local-fast",
            )
        self.assertTrue(cards_only)
        self.assertTrue(any("cards" in item.lower() for item in warnings))
        self.assertTrue(all(item["source"] == "reelforge-card" for item in assignments.values()))


class VoiceFallbackTests(unittest.TestCase):
    def test_basic_voice_label(self):
        with tempfile.TemporaryDirectory() as tmp, \
                patch("reelforge.speech._kokoro", return_value=None), \
                patch("reelforge.speech._edge_tts_cli", return_value=None), \
                patch("reelforge.speech._basic_voice", return_value=True), \
                patch("reelforge.speech.wav_duration", return_value=1.2):
            dest = Path(tmp) / "voice.wav"
            dest.write_bytes(b"RIFF" + b"\x00" * 40)
            duration, engine, words = speech.synthesize("hello there", dest)
        self.assertEqual(engine, "basic voice")
        self.assertGreater(duration, 0)
        self.assertEqual(words, [])


class HumanErrorTests(unittest.TestCase):
    def test_human_sentences(self):
        self.assertIn("Download ffmpeg", errors.human("ffmpeg not found on PATH"))
        self.assertIn("retry", errors.human("Checksum did not match").lower())
        self.assertIn("stills-only", errors.human("CUDA out of memory"))
        self.assertIn("basic", errors.human("kokoro timed out").lower())
        self.assertIn("fallback", errors.human("mystery"))


if __name__ == "__main__":
    unittest.main()
