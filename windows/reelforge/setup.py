from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen

from reelforge.paths import models_dir, package_dir, repo_root


def manifest_path() -> Path:
    bundled = package_dir() / "models" / "manifest.json"
    if bundled.exists():
        return bundled
    return repo_root() / "Sources" / "ReelForgeCore" / "Resources" / "models" / "manifest.json"


def load_manifest() -> dict[str, Any]:
    return json.loads(manifest_path().read_text(encoding="utf-8"))


def probe_hardware() -> dict[str, Any]:
    if raw := os.environ.get("REELFORGE_FAKE_HW"):
        return json.loads(raw)
    nvidia, vram = _nvidia()
    return {
        "os": platform.system(),
        "nvidia": nvidia,
        "vramGB": vram,
        "appleGPU": platform.system() == "Darwin" and platform.machine().lower() in {"arm64", "aarch64"},
        "ramGB": _ram_gb(),
        "diskFreeGB": _disk_free_gb(models_dir()),
        "modelsDir": str(models_dir()),
    }


def recommend_pack(hardware: dict[str, Any] | None = None) -> str:
    hw = hardware or probe_hardware()
    if hw.get("nvidia") and float(hw.get("vramGB") or 0) >= 8:
        return "fast-video"
    if hw.get("appleGPU"):
        return "fast-image"
    return "instant"


def show_quality(hardware: dict[str, Any] | None = None) -> bool:
    hw = hardware or probe_hardware()
    return float(hw.get("vramGB") or 0) >= 16


def visible_packs(hardware: dict[str, Any] | None = None, manifest: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    hw = hardware or probe_hardware()
    doc = manifest or load_manifest()
    out = []
    for pack in doc.get("packs") or []:
        need = pack.get("hiddenUnlessVramGB")
        if need is not None and float(hw.get("vramGB") or 0) < float(need):
            continue
        out.append(pack)
    return out


def wizard_state() -> dict[str, Any]:
    from reelforge import models
    from reelforge.settings_store import load

    settings = load()
    hardware = probe_hardware()
    catalog = models.scan(settings.get("modelsDir") or str(models_dir()))
    return {
        "title": "Set up ReelForge in one click",
        "hardware": hardware,
        "recommended": recommend_pack(hardware),
        "showQuality": show_quality(hardware),
        "packs": visible_packs(hardware),
        "files": load_manifest().get("files") or [],
        "catalog": catalog,
        "modelsDir": str(models_dir()),
        "setupComplete": bool(settings.get("setupComplete")),
    }


def mark_complete() -> dict[str, Any]:
    from reelforge.settings_store import save
    return save({"setupComplete": True})


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_file(
    url: str,
    dest: Path,
    expected_sha256: str = "",
    progress: list[dict[str, Any]] | None = None,
    pause: dict[str, bool] | None = None,
    opener=None,
) -> Path:
    """Resume-friendly download. opener is injectable so CI never hits the network."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    existing = part.stat().st_size if part.exists() else 0
    headers = {"User-Agent": "ReelForge/1.0"}
    if existing:
        headers["Range"] = f"bytes={existing}-"
    fetch = opener or _default_open
    response = fetch(url, headers)
    mode = "ab" if existing and getattr(response, "status", 200) == 206 else "wb"
    if mode == "wb" and part.exists():
        existing = 0
    written = existing
    total = existing + int(getattr(response, "headers", {}).get("Content-Length") or 0)
    with part.open(mode) as handle:
        while True:
            if pause and pause.get("paused"):
                break
            chunk = response.read(1024 * 256)
            if not chunk:
                break
            handle.write(chunk)
            written += len(chunk)
            if progress is not None:
                progress.append({"bytes": written, "total": total, "path": str(dest)})
    if pause and pause.get("paused"):
        return part
    part.replace(dest)
    if expected_sha256 and sha256_file(dest).lower() != expected_sha256.lower():
        dest.unlink(missing_ok=True)
        raise RuntimeError("Checksum did not match. The download was deleted so you can retry.")
    return dest


def download_pack(pack_id: str, progress: list[dict[str, Any]] | None = None, opener=None) -> dict[str, Any]:
    doc = load_manifest()
    files = [item for item in doc.get("files") or [] if item.get("pack") == pack_id or item.get("id") in _pack_file_ids(doc, pack_id)]
    results = []
    for item in files:
        urls = [u for u in (item.get("urls") or []) if u]
        dest = models_dir() / item["dest"]
        if dest.exists():
            results.append({"id": item["id"], "ready": True, "path": str(dest), "skipped": True})
            continue
        if not urls:
            results.append({"id": item["id"], "ready": False, "note": item.get("note") or "Packaged at build — no download URL."})
            continue
        path = download_file(urls[0], dest, item.get("sha256") or "", progress, opener=opener)
        results.append({"id": item["id"], "ready": path.exists(), "path": str(path)})
    return {"pack": pack_id, "files": results}


def _pack_file_ids(doc: dict[str, Any], pack_id: str) -> list[str]:
    for pack in doc.get("packs") or []:
        if pack.get("id") == pack_id:
            return list(pack.get("fileIds") or [])
    return []


def _default_open(url: str, headers: dict[str, str]):
    request = Request(url, headers=headers)
    return urlopen(request, timeout=30)


def _nvidia() -> tuple[bool, float]:
    binary = shutil.which("nvidia-smi")
    if not binary:
        return False, 0.0
    try:
        import subprocess
        result = subprocess.run(
            [binary, "--query-gpu=memory.total", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode != 0:
            return True, 0.0
        mb = float((result.stdout or "0").splitlines()[0].strip() or 0)
        return True, round(mb / 1024.0, 1)
    except Exception:
        return True, 0.0


def _ram_gb() -> float:
    try:
        if hasattr(os, "sysconf"):
            pages = os.sysconf("SC_PHYS_PAGES")
            size = os.sysconf("SC_PAGE_SIZE")
            return round((pages * size) / (1024 ** 3), 1)
    except Exception:
        pass
    return 0.0


def _disk_free_gb(path: Path) -> float:
    try:
        usage = shutil.disk_usage(path)
        return round(usage.free / (1024 ** 3), 1)
    except Exception:
        return 0.0
