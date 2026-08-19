import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from reelforge import align, edl, encoder, footage
from reelforge.captions import apply_tts_words, force_align_to_script


class EditListTests(unittest.TestCase):
    def test_filter_complex_is_one_encode_sidechain_and_punch_in(self):
        document = self._sample()
        graph = edl.filter_complex(document, "/tmp/fonts", True)
        self.assertIn("sidechaincompress", graph)
        self.assertIn("ass=", graph)
        self.assertIn("yuv420p", graph)
        self.assertIn("zoompan", graph)
        self.assertIn("unsharp", graph)
        self.assertNotIn("fade=t=in", graph)
        self.assertFalse(document["hook"]["fadeFromBlack"])
        self.assertGreaterEqual(document["hook"]["punchIn"], 1.08)
        self.assertLessEqual(document["hook"]["punchIn"], 1.15)
        self.assertIn("libx264", edl.ENCODER_WHITELIST)
        self.assertIn("libx264", encoder.ENCODER_WHITELIST)
        self.assertTrue(document["audioMaster"])
        self.assertEqual(document["duck"]["speechDb"], -18)
        self.assertEqual(document["duck"]["gapDb"], -8)
        self.assertEqual(document["duck"]["mode"], "sidechaincompress")
        args = encoder.video_args("libx264")
        self.assertIn("yuv420p", args)
        self.assertIn("+faststart", args)

    def test_json_round_trip(self):
        document = self._sample()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "edl.json"
            edl.write(document, path)
            loaded = edl.load(path)
        self.assertEqual(loaded["width"], 1080)
        self.assertEqual(loaded["clips"][0]["role"], "hook")
        self.assertFalse(loaded["hook"]["fadeFromBlack"])
        raw = json.dumps(loaded)
        self.assertIn("sidechaincompress", raw)
        self.assertIn("yuv420p", raw)

    def test_force_align_keeps_script_tokens(self):
        timed = [
            {"word": "uh", "start": 0.0, "duration": 0.1},
            {"word": "stop", "start": 0.12, "duration": 0.2},
            {"word": "scrolling", "start": 0.35, "duration": 0.4},
            {"word": "now", "start": 0.8, "duration": 0.3},
            {"word": "like", "start": 1.2, "duration": 0.2},
        ]
        mapped = align.force_align_tokens(["Stop", "scrolling", "now"], timed)
        self.assertEqual([item["word"] for item in mapped], ["Stop", "scrolling", "now"])
        cues = [{"text": "Stop scrolling now", "start": 0, "duration": 1.5, "words": [
            {"word": "Stop", "start": 0, "duration": 0.5},
            {"word": "scrolling", "start": 0.5, "duration": 0.5},
            {"word": "now", "start": 1.0, "duration": 0.5},
        ]}]
        aligned = force_align_to_script(cues, timed)
        self.assertEqual(aligned[0]["text"], "Stop scrolling now")
        self.assertEqual([w["word"] for w in aligned[0]["words"]], ["Stop", "scrolling", "now"])
        replaced = apply_tts_words(cues, timed)
        self.assertNotIn("uh", replaced[0]["text"].lower())
        self.assertNotIn("like", replaced[0]["text"].lower())

    def test_unique_source_does_not_replay_used_id(self):
        self.assertEqual(footage.first_unused([{"id": 11}, {"id": 22}], {11})["id"], 22)
        self.assertIsNone(footage.first_unused([{"id": 11}], {11}))
        self.assertIsNone(footage.first_unused([{"id": 0}], set()))

    def test_speech_module_does_not_vendor_python_tts_packages(self):
        src = (Path(__file__).resolve().parents[1] / "reelforge" / "speech.py").read_text(encoding="utf-8")
        self.assertNotIn("import pyttsx3", src)
        self.assertNotIn("import edge_tts", src)
        self.assertNotIn("win32com", src)
        self.assertIn("basic voice", src)
        self.assertIn("System.Speech", src)
        req = (Path(__file__).resolve().parents[1] / "requirements.txt").read_text(encoding="utf-8")
        self.assertFalse(any(line.strip().startswith("edge-tts") for line in req.splitlines()))
        self.assertFalse(any(line.strip().startswith("pyttsx3") for line in req.splitlines()))

    def _sample(self):
        return edl.build(
            [
                {"id": "b0", "role": "hook", "start": 0, "duration": 2, "text": "Stop scrolling"},
                {"id": "b1", "role": "body", "start": 2, "duration": 3, "text": "Daylight is free"},
            ],
            {
                "b0": {"path": "hook.mp4", "kind": "video", "clipID": "pexels-1"},
                "b1": {"path": "body.png", "kind": "image", "clipID": "qwen-1"},
            },
            Path("voice.wav"),
            Path("music.wav"),
            5,
            1080,
            1920,
            {"footage": {"kenBurns": True, "zoomPulse": True, "overlayGrain": False}, "colorGrade": {"contrast": 1.08, "saturation": 1.12, "warmth": 0.2, "vignette": 0.35}},
            Path("captions.ass"),
            {"id": "tiktok-classic-outline", "renderer": "ass"},
        )


if __name__ == "__main__":
    unittest.main()
