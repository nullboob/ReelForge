import os
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from reelforge import infer, models


class ModelCatalogTests(unittest.TestCase):
    def test_scan_marks_existing_weights_ready(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "ltx-2.3-22b-distilled.safetensors").write_bytes(b"fake")
            (root / "qwen-image.safetensors").write_bytes(b"fake")
            catalog = models.scan(roots=[root])
            self.assertTrue(catalog["videoReady"])
            self.assertTrue(catalog["imageReady"])
            self.assertTrue(catalog["anyReady"])
            ids = {item["id"]: item for item in catalog["slots"]}
            self.assertTrue(ids["ltx-distilled"]["ready"])
            self.assertTrue(ids["qwen-image"]["ready"])
            self.assertFalse(ids["wan-22"]["ready"])

    def test_scan_marks_gguf_video_ready(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "ltx-2.3-22b-distilled-1.1-Q5_K_S.gguf").write_bytes(b"fake")
            catalog = models.scan(roots=[root])
            self.assertTrue(catalog["videoReady"])
            ids = {item["id"]: item for item in catalog["slots"]}
            self.assertTrue(ids["ltx-gguf"]["ready"])

    def test_default_scan_roots_include_existing_windows_folders(self):
        roots = [str(path).replace("\\", "/") for path in models.default_scan_roots()]
        self.assertTrue(any("ComfyUI_windows_portable_nvidia" in item for item in roots))
        self.assertTrue(any(item.rstrip("/").endswith("D:") or "/D:" in item or item.endswith("D:/") for item in roots))

    def test_aligned_size_and_frame_count(self):
        width, height = infer.aligned_size(1080, 1920)
        self.assertEqual(width % 32, 0)
        self.assertEqual(height % 32, 0)
        frames = infer.frame_count(3.0)
        self.assertEqual(frames % 8, 1)
        self.assertGreaterEqual(frames, 9)

    def test_infer_skips_without_runtime_or_when_forced(self):
        previous = os.environ.get("REELFORGE_SKIP_INFER")
        os.environ["REELFORGE_SKIP_INFER"] = "1"
        try:
            with tempfile.TemporaryDirectory() as tmp:
                dest = Path(tmp) / "out.mp4"
                self.assertFalse(infer.generate_video("a walking shot", dest))
                self.assertFalse(dest.exists())
                self.assertFalse(infer.generate_image("a still", dest.with_suffix(".png")))
        finally:
            if previous is None:
                os.environ.pop("REELFORGE_SKIP_INFER", None)
            else:
                os.environ["REELFORGE_SKIP_INFER"] = previous
        self.assertFalse(infer.generate_wan_video("later", Path("nope.mp4")))

    def test_core_requirements_do_not_vendor_diffusion(self):
        text = (Path(__file__).resolve().parents[1] / "requirements.txt").read_text(encoding="utf-8")
        for banned in ("torch", "diffusers", "ltx-pipelines", "comfy", "edge-tts", "pyttsx3", "moviepy", "remotion"):
            self.assertNotIn(banned + "==", text.lower().replace("_", "-"))
            self.assertFalse(any(
                line.strip().lower().startswith(banned) and not line.strip().startswith("#")
                for line in text.splitlines()
            ))


if __name__ == "__main__":
    unittest.main()
