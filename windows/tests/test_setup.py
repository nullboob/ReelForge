import hashlib
import io
import json
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from reelforge import ffmpeg_bundle, setup


class FakeResponse:
    def __init__(self, payload: bytes, status: int = 200):
        self._buf = io.BytesIO(payload)
        self.status = status
        self.headers = {"Content-Length": str(len(payload))}

    def read(self, n: int = -1) -> bytes:
        return self._buf.read(n)


class SetupWizardTests(unittest.TestCase):
    def test_recommend_instant_without_gpu(self):
        self.assertEqual(setup.recommend_pack({"nvidia": False, "vramGB": 0, "appleGPU": False}), "instant")

    def test_recommend_fast_video_on_nvidia_8gb(self):
        self.assertEqual(setup.recommend_pack({"nvidia": True, "vramGB": 8, "appleGPU": False}), "fast-video")

    def test_recommend_fast_image_on_apple_gpu(self):
        self.assertEqual(setup.recommend_pack({"nvidia": False, "vramGB": 0, "appleGPU": True}), "fast-image")

    def test_quality_hidden_unless_16gb(self):
        self.assertFalse(setup.show_quality({"vramGB": 8}))
        self.assertTrue(setup.show_quality({"vramGB": 16}))
        packs = setup.visible_packs({"vramGB": 8})
        self.assertFalse(any(item["id"] == "quality-video" for item in packs))
        packs16 = setup.visible_packs({"vramGB": 16})
        self.assertTrue(any(item["id"] == "quality-video" for item in packs16))

    def test_fake_hw_env(self):
        os.environ["REELFORGE_FAKE_HW"] = json.dumps({"nvidia": True, "vramGB": 12, "appleGPU": False, "ramGB": 32, "diskFreeGB": 200})
        try:
            hw = setup.probe_hardware()
            self.assertEqual(setup.recommend_pack(hw), "fast-video")
        finally:
            os.environ.pop("REELFORGE_FAKE_HW", None)

    def test_manifest_urls_are_empty_or_known_hosts(self):
        doc = setup.load_manifest()
        self.assertEqual(doc["title"], "Set up ReelForge in one click")
        for item in doc["files"]:
            for url in item.get("urls") or []:
                self.assertTrue(
                    url.startswith("https://huggingface.co/") or url.startswith("https://github.com/BtbN/"),
                    url,
                )
            if not item.get("urls"):
                self.assertTrue(item.get("note"), f"{item['id']} needs a packaged-at-build note")

    def test_download_resume_and_checksum(self):
        payload = b"reelforge-pack-bytes-0123456789"
        digest = hashlib.sha256(payload).hexdigest()
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "clip.bin"
            part = dest.with_suffix(".bin.part")
            part.write_bytes(payload[:10])

            def opener(url, headers):
                self.assertIn("Range", headers)
                return FakeResponse(payload[10:], status=206)

            path = setup.download_file(url="https://example.invalid/file.bin", dest=dest, expected_sha256=digest, opener=opener)
            self.assertEqual(path.read_bytes(), payload)

            dest.unlink()
            def bad_opener(url, headers):
                return FakeResponse(payload, status=200)
            with self.assertRaises(RuntimeError):
                setup.download_file(url="https://example.invalid/file.bin", dest=dest, expected_sha256="0" * 64, opener=bad_opener)
            self.assertFalse(dest.exists())

    def test_download_pause_leaves_part_file(self):
        payload = b"abcdefghij" * 400
        pause = {"paused": False}

        class Once(FakeResponse):
            def read(self, n: int = -1) -> bytes:
                chunk = super().read(n)
                pause["paused"] = True
                return chunk

        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "big.bin"
            path = setup.download_file(
                url="https://example.invalid/big.bin",
                dest=dest,
                pause=pause,
                opener=lambda url, headers: Once(payload),
            )
            self.assertTrue(str(path).endswith(".part"))
            self.assertFalse(dest.exists())
            self.assertGreater(path.stat().st_size, 0)

    def test_download_pack_skips_empty_urls(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["REELFORGE_DATA_DIR"] = tmp
            try:
                result = setup.download_pack("quality-video", opener=lambda url, headers: FakeResponse(b"nope"))
            finally:
                os.environ.pop("REELFORGE_DATA_DIR", None)
        notes = [item.get("note") for item in result["files"]]
        self.assertTrue(any(notes))
        self.assertFalse(any(item.get("ready") for item in result["files"]))

    def test_download_can_pause_and_retry(self):
        payload = b"abcdefghij" * 200
        pause = {"paused": False}
        reads = {"n": 0}

        class Slow(FakeResponse):
            def read(self, n: int = -1) -> bytes:
                reads["n"] += 1
                if reads["n"] >= 2:
                    pause["paused"] = True
                return super().read(256)

        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "pack.bin"
            part = setup.download_file(
                "https://example.invalid/pack.bin", dest, pause=pause, opener=lambda url, headers: Slow(payload)
            )
            self.assertTrue(str(part).endswith(".part"))
            self.assertFalse(dest.exists())
            pause["paused"] = False
            existing = part.stat().st_size

            def resume(url, headers):
                start = 0
                if "Range" in headers:
                    start = int(headers["Range"].split("=")[1].rstrip("-"))
                return FakeResponse(payload[start:], status=206 if start else 200)

            done = setup.download_file("https://example.invalid/pack.bin", dest, opener=resume)
            self.assertEqual(done.read_bytes(), payload)
            self.assertGreater(existing, 0)


class FfmpegBundleTests(unittest.TestCase):
    def test_install_from_tiny_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / "ffmpeg.zip"
            with zipfile.ZipFile(archive, "w") as zipped:
                zipped.writestr("ffmpeg-master/bin/ffmpeg", b"fake-ffmpeg")
            path = ffmpeg_bundle.install_from_zip(archive, dest_dir=Path(tmp) / "bin")
            self.assertTrue(Path(path).exists())
            self.assertGreater(Path(path).stat().st_size, 0)


if __name__ == "__main__":
    unittest.main()
