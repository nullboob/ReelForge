# ReelForge for Windows

Same product as the Mac app: you draft a script, click **Accept**, then we render a YouTube-ready pack on this PC. Not a timeline editor. Not a silent topic→MP4 firehose.

The **shipped** installer is a PyInstaller onedir + Inno Setup script. Build those on a Windows box — see [`docs/SHIP.md`](../docs/SHIP.md). Linux CI cannot emit `ReelForge.exe`.

## Dev run (source)

Windows 10/11, Python 3.12 (user install). ffmpeg is optional: the first-run wizard can drop an LGPL build into `%LOCALAPPDATA%\ReelForge\bin`.

```bat
cd windows
py -3.12 -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m reelforge
```

That command opens a **desktop window** (pywebview). If WebView2/pywebview fails, it opens `http://127.0.0.1:8765` in your default browser and keeps the server running.

## First-run wizard

Title: **Set up ReelForge in one click**. Instant (0 GB) always works. Fast Image / Fast Video are optional one-click downloads into `%LOCALAPPDATA%\ReelForge\models` (no admin). Quality Video is hidden unless VRAM ≥ 16 GB. “I already have models” scans known filenames, including `E:\ComfyUI_windows_portable_nvidia\ComfyUI\models` and `D:\`.

## First video

1. Finish or skip the wizard (Instant is enough)
2. Pick **Viral Hook**
3. Type `3 reasons your morning walk beats the gym`
4. **Draft script**
5. Edit the desk if you want, then **Accept script**
6. Play the MP4, copy the publish pack, **Export** to reveal the folder in Explorer

Exports land in `%USERPROFILE%\Videos\ReelForge\<timestamp-slug>\` as MP4 + thumbnail + SRT + JSON + `credits.json`.

## Optional

| Job | Where |
| --- | --- |
| Better TTS | Kokoro-FastAPI at `http://127.0.0.1:8880/v1/audio/speech`, else edge-tts CLI, else **basic voice** |
| Scripts | Ollama at `localhost:11434` |
| Stock B-roll | Pexels key in Settings (`Authorization` header), Pixabay second |
| Local video / stills | First-run wizard or Settings → Model Manager. Point `modelsDir` at weights you already have. |

Core works with **zero** local diffusion models. Weights are never in the exe. `torch` / `diffusers` / `ltx-pipelines` are optional GPU-helper extras — do not add them to `requirements.txt`.

Piper is **not** embedded. Unsplash is off. Music is a programmatic original-safe bed or a folder you import. Duck 8–12 dB under VO.

## Tests (portable)

```bat
cd windows
set REELFORGE_SKIP_INFER=1
set REELFORGE_SKIP_COMFY=1
set REELFORGE_SKIP_ACE=1
.venv\Scripts\python -m unittest discover -s tests -v
```

Storyboard hook + caption split + publish pack + wizard mocks do not need ffmpeg or network.
