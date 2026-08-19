import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from reelforge import comfy
from reelforge import footage


class FakeResponse:
    def __init__(self, status=200, payload=None, content=b""):
        self.status_code = status
        self._payload = payload if payload is not None else {}
        self.content = content

    def json(self):
        return self._payload


class FakeClient:
    def __init__(self, *args, **kwargs):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def get(self, url, params=None):
        if url.endswith("/system_stats"):
            return FakeResponse(200, {"system": {"os": "win"}})
        if "/models/" in url:
            return FakeResponse(200, ["ltx-2.3-22b-distilled.safetensors", "wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors", "qwen_image_fp8_e4m3fn.safetensors"])
        if "/history/" in url:
            return FakeResponse(200, {
                "prompt-1": {
                    "outputs": {
                        "9": {"videos": [{"filename": "out.mp4", "subfolder": "", "type": "output"}]}
                    }
                }
            })
        if url.endswith("/view") or "/view" in url:
            return FakeResponse(200, content=b"0" * 500)
        return FakeResponse(404)

    def post(self, url, json=None):
        if url.endswith("/prompt"):
            return FakeResponse(200, {"prompt_id": "prompt-1"})
        return FakeResponse(404)


class ComfyClientTests(unittest.TestCase):
    def test_fill_template_replaces_ints_in_place(self):
        node = {"inputs": {"width": "{{WIDTH}}", "text": "hello {{PROMPT}}"}}
        filled = comfy.fill_template(node, {"WIDTH": 1088, "PROMPT": "walk"})
        self.assertEqual(filled["inputs"]["width"], 1088)
        self.assertEqual(filled["inputs"]["text"], "hello walk")

    def test_load_workflow_has_placeholders(self):
        workflow = comfy.load_workflow("ltx-fast")
        blob = str(workflow)
        self.assertIn("{{PROMPT}}", blob)
        self.assertIn("{{CKPT}}", blob)
        self.assertIn("EmptyLTXVLatentVideo", blob)

    def test_generate_video_uses_queue_api(self):
        previous = os.environ.pop("REELFORGE_SKIP_COMFY", None)
        try:
            with tempfile.TemporaryDirectory() as tmp, patch("reelforge.comfy.httpx.Client", FakeClient):
                dest = Path(tmp) / "ltx.mp4"
                self.assertTrue(comfy.generate_video("handheld walk", dest, kind="ltx", seconds=3))
                self.assertTrue(dest.exists())
                self.assertGreaterEqual(dest.stat().st_size, 400)
        finally:
            if previous is not None:
                os.environ["REELFORGE_SKIP_COMFY"] = previous

    def test_probe_reads_system_stats(self):
        previous = os.environ.pop("REELFORGE_SKIP_COMFY", None)
        try:
            with patch("reelforge.comfy.httpx.Client", FakeClient):
                status = comfy.probe("http://127.0.0.1:8188")
            self.assertTrue(status["up"])
            self.assertTrue(status["ltx"])
            self.assertTrue(status["wan"])
            self.assertTrue(status["qwen"])
        finally:
            if previous is not None:
                os.environ["REELFORGE_SKIP_COMFY"] = previous

    def test_skip_env_does_not_touch_network(self):
        os.environ["REELFORGE_SKIP_COMFY"] = "1"
        try:
            self.assertFalse(comfy.probe()["up"])
            with tempfile.TemporaryDirectory() as tmp:
                self.assertFalse(comfy.generate_video("x", Path(tmp) / "no.mp4"))
        finally:
            os.environ.pop("REELFORGE_SKIP_COMFY", None)


class FootageLadderTests(unittest.TestCase):
    def test_local_kind_fast_is_hook_only_ltx(self):
        self.assertEqual(footage.local_kind(0, "local-fast"), "ltx")
        self.assertEqual(footage.local_kind(1, "local-fast"), "qwen")
        self.assertEqual(footage.local_kind(0, "stock-first"), "ltx")
        self.assertEqual(footage.local_kind(4, "stock-first"), "qwen")

    def test_local_kind_quality_is_wan_for_hook_and_two_body(self):
        self.assertEqual(footage.local_kind(0, "local-quality"), "wan")
        self.assertEqual(footage.local_kind(2, "local-quality"), "wan")
        self.assertEqual(footage.local_kind(3, "local-quality"), "qwen")

    def test_pexels_hit_skips_comfy(self):
        beats = [{"id": "b0", "text": "morning walk outside", "start": 0, "duration": 3, "unsplashQuery": "morning walk"}]
        preset = {"aiImageStyleSuffix": "photoreal"}
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
                patch("reelforge.comfy.probe", return_value={"up": True, "ltx": True, "wan": True, "qwen": True, "url": "http://127.0.0.1:8188"}), \
                patch("reelforge.comfy.generate_video", fake_video), \
                patch("reelforge.comfy.generate_image", fake_image):
            assignments, ledger, warnings, cards_only = footage.gather(
                beats, preset, "9:16", Path(tmp),
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

    def test_offline_without_models_paints_instead_of_comfy(self):
        beats = [
            {"id": "b0", "text": "morning walk", "start": 0, "duration": 3, "unsplashQuery": "walk"},
            {"id": "b1", "text": "second beat", "start": 3, "duration": 3, "unsplashQuery": "path"},
        ]
        preset = {"aiImageStyleSuffix": "photoreal"}
        with tempfile.TemporaryDirectory() as tmp, \
                patch("reelforge.comfy.probe", return_value={"up": False, "ltx": False, "wan": False, "qwen": False, "url": "http://127.0.0.1:8188"}), \
                patch("reelforge.infer.generate_video", return_value=False), \
                patch("reelforge.infer.generate_image", return_value=False):
            assignments, ledger, warnings, cards_only = footage.gather(
                beats, preset, "9:16", Path(tmp),
                pexels_key=None,
                use_pexels=True,
                channel_name="test",
                pixabay_key=None,
                use_pixabay=True,
                use_local_models=True,
                local_mode="local-fast",
            )
        self.assertFalse(cards_only)
        self.assertFalse(any("ComfyUI is down" in item for item in warnings))
        self.assertTrue(all(item["source"] == "painted" for item in assignments.values()))
        self.assertTrue(any(entry.get("credit") == "Painted art" for entry in ledger))
        self.assertFalse(any(entry.get("credit") in {"LTX-2.3 local", "Wan 2.2 local", "Qwen Image local"} for entry in ledger))


if __name__ == "__main__":
    unittest.main()
