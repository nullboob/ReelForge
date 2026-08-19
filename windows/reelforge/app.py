from __future__ import annotations

import os
import socket
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from reelforge.director import DIRECTOR
from reelforge.paths import videos_dir, web_dir
from reelforge.presets import load_presets
from reelforge.settings_store import load as load_settings
from reelforge.settings_store import save as save_settings
from reelforge.storyboard import StoryboardError

app = FastAPI(title="ReelForge")
app.mount("/static", StaticFiles(directory=web_dir()), name="static")


@app.get("/")
def index() -> FileResponse:
    return FileResponse(web_dir() / "index.html")


@app.get("/api/bootstrap")
def bootstrap() -> dict:
    return {
        "presets": load_presets(),
        "status": DIRECTOR.status(),
        **DIRECTOR.snapshot(),
    }


@app.get("/api/progress")
def progress() -> dict:
    return DIRECTOR.snapshot()


@app.post("/api/new")
def new_project() -> dict:
    return DIRECTOR.new_project()


@app.post("/api/draft")
def draft(payload: dict) -> dict:
    try:
        return DIRECTOR.draft(payload)
    except (ValueError, StoryboardError) as exc:
        raise HTTPException(400, str(exc)) from exc


@app.post("/api/accept")
def accept(payload: dict) -> dict:
    try:
        return DIRECTOR.accept(payload)
    except (ValueError, StoryboardError) as exc:
        raise HTTPException(400, str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(500, str(exc)) from exc


@app.post("/api/settings")
def settings(payload: dict) -> dict:
    return save_settings(payload)


@app.get("/api/settings")
def get_settings() -> dict:
    return load_settings()


@app.get("/api/models")
def get_models() -> dict:
    settings = load_settings()
    from reelforge.infer import available
    return available(settings.get("modelsDir") or None)


@app.get("/api/comfy")
def comfy_status() -> dict:
    from reelforge import comfy
    settings = load_settings()
    return comfy.probe(settings.get("comfyUrl"))


@app.post("/api/models")
def post_models(payload: dict) -> dict:
    if "modelsDir" in payload:
        save_settings({"modelsDir": payload.get("modelsDir") or ""})
    settings = load_settings()
    from reelforge.infer import available
    return available(settings.get("modelsDir") or None)


@app.post("/api/reveal")
def reveal() -> dict:
    path = DIRECTOR.project.get("exportPath")
    if not path or not Path(path).exists():
        raise HTTPException(404, "Nothing exported yet.")
    folder = str(Path(path).parent)
    if sys.platform == "win32":
        subprocess.Popen(["explorer", "/select,", path])
    elif sys.platform == "darwin":
        subprocess.Popen(["open", "-R", path])
    else:
        subprocess.Popen(["xdg-open", folder])
    return {"ok": True, "path": path}


@app.get("/api/media")
def media() -> FileResponse:
    path = DIRECTOR.project.get("exportPath")
    if not path or not Path(path).exists():
        raise HTTPException(404, "No export")
    return FileResponse(path, media_type="video/mp4")


def _free_port(preferred: int = 8765) -> int:
    for port in range(preferred, preferred + 20):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                sock.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    raise RuntimeError("No free port for ReelForge")


def _wait_up(url: str, timeout: float = 8.0) -> None:
    import httpx
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if httpx.get(url, timeout=0.4).status_code < 500:
                return
        except Exception:
            time.sleep(0.15)
    raise RuntimeError(f"ReelForge server did not start at {url}")


def main() -> None:
    videos_dir()
    port = int(os.environ.get("REELFORGE_PORT") or _free_port())
    url = f"http://127.0.0.1:{port}"

    def serve() -> None:
        import uvicorn
        uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    _wait_up(url + "/")

    if os.environ.get("REELFORGE_NO_WINDOW") == "1":
        print(f"ReelForge server {url}")
        thread.join()
        return

    try:
        import webview
        webview.create_window("ReelForge", url, width=1440, height=920, min_size=(1200, 800))
        webview.start()
        return
    except Exception as exc:
        print(f"pywebview failed ({exc}); opening the default browser.")
        webbrowser.open(url)
        try:
            thread.join()
        except KeyboardInterrupt:
            return
