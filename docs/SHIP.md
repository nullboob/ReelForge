# Shipping ReelForge

Same product on Windows and Mac: a small installer, a one-click first-run wizard, and a working editor **without** GPU weights. This environment is Linux CI. It does **not** produce `ReelForge.exe` or a signed `.app`. Build those on the matching OS.

## What is NOT in the installer

- No ComfyUI, no node graph, no 80 GB weight dump
- No PyTorch, diffusers, `ltx-pipelines`, or Wan/Qwen checkpoints
- No Hugging Face cache, no admin requirement for model downloads
- Fast Video is the **GGUF (~15 GB)**, not the official 46.1 GB distilled file
- Qwen Image base and Wan 2.2 have **empty download URLs** (multi-file repos). The wizard scans known filenames or you point at a folder you already have

GPU packs are optional upgrades the wizard offers after the app already works.

## What customers get on first open

Instant pack (0 GB extra): Pexels/Pixabay if a key is set, otherwise painted full-bleed art + captions + neural TTS (Kokoro sidecar → edge-tts CLI → OS **basic voice**). Export still finishes.

## First-run wizard (same copy)

Title: **Set up ReelForge in one click**

| Pack | Size | When |
| --- | --- | --- |
| Instant | 0 GB | Always. Default if no NVIDIA 8 GB+ and no Apple GPU |
| Fast Image | ~8–12 GB | Qwen Lightning LoRA (verified HF URL) + Qwen base if already on disk |
| Fast Video | ~15–20 GB | LTX-2.3 distilled **GGUF** (verified HF URL) |
| Quality Video | 24 GB+ | Wan 2.2 4-step. **Hidden unless VRAM ≥ 16 GB** |

“I already have models” opens a folder picker, scans known filenames, marks Ready. On Rahul’s PC the scanner also looks at `E:\ComfyUI_windows_portable_nvidia\ComfyUI\models` and `D:\`.

Model store (never needs admin):

- Windows: `%LOCALAPPDATA%\ReelForge\models`
- Mac: `~/Library/Application Support/ReelForge/models`

Shared manifest: `windows/reelforge/models/manifest.json` and `Sources/ReelForgeCore/Resources/models/manifest.json`. `sha256` is empty unless we have a real hash. Empty `urls` mean “packaged at build / scan existing” — do not invent 404s.

## Runtime fallbacks

| Stage | Order |
| --- | --- |
| Footage | User files → Pexels/Pixabay → local LTX (if Ready) → Qwen still + Ken Burns → painted full-bleed art → cards only **with a warning** |
| Voice | Kokoro sidecar → edge-tts CLI (if network) → OS neural/SAPI labeled **basic voice** |
| Captions | ASS karaoke → Pillow PNG overlay → SRT sidecar if burn fails. No overlapping cues. No letterboxed 9:16 |
| Encode | NVENC → QSV/AMF → libx264. Missing ffmpeg → one-click **LGPL** static into AppData (BtbN), not a system install |
| GPU OOM | Unload, retry smaller size, then stills-only |
| Offline | Instant still works with cached stock or painted art |

Errors never dead-end. Windows `reelforge.errors.human()` and the Mac toast turn failures into a sentence. Log: `%LOCALAPPDATA%\ReelForge\reelforge.log` / `~/Library/Application Support/ReelForge/reelforge.log`.

## Windows exe (build on a Windows box)

Linux CI cannot emit a PE binary. On Windows 10/11 with Python 3.12 (user install):

```powershell
cd windows
.\build-windows.ps1
```

That script:

1. Creates `.venv`, installs `windows/requirements.txt` + PyInstaller
2. Builds **onedir** `dist\ReelForge\ReelForge.exe` from `ReelForge.spec`
3. If Inno Setup 6 is installed, compiles `installer\ReelForge.iss` → `dist-installer\ReelForge-Setup.exe` with `PrivilegesRequired=lowest`

The onedir bundles: pywebview GUI, FastAPI backend, OFL fonts, caption catalog, model **manifest** (not weights). Optionally drop an LGPL `ffmpeg.exe` in `windows\vendor\ffmpeg\` before the spec run; otherwise the wizard downloads ffmpeg into AppData.

**Smoke checklist (Windows box, no 40 GB download):**

1. Launch `ReelForge.exe` with no Python on PATH
2. Wizard title is “Set up ReelForge in one click”
3. Instant is recommended on a machine without NVIDIA 8 GB+
4. Skip / Instant → main editor (presets, caption grid, Draft, Accept, preview, publish pack)
5. Accept a 15s Viral Hook with no Pexels key → painted art, not a dead-end
6. Settings → toast on a forced ffmpeg miss offers Download ffmpeg
7. Confirm `%LOCALAPPDATA%\ReelForge\reelforge.log` exists after an error
8. Confirm the exe folder has **no** `torch`, no `.safetensors`, no ComfyUI

GPU helper (torch + LTX/Qwen) is a **later** download, never this exe.

Dev loop without the installer:

```bat
cd windows
py -3.12 -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m reelforge
```

## Mac app (build on a Mac)

Linux CI does **not** compile the `.app`. XcodeGen must still generate:

```bash
brew install xcodegen
xcodegen generate
open ReelForge.xcodeproj
```

Xcode 15+, macOS 14+, Apple Silicon first. Product is the native SwiftUI app (not a Python wrap). Same wizard copy, same caption catalog JSON, same EDL, same manifest.

Mac one-click download uses URLSession into Application Support for files that have real HF URLs (Lightning LoRA, LTX GGUF). Files with empty URLs stay “scan existing / packaged at build.” ffmpeg is not required for AVFoundation export; if you install ffmpeg for edge-tts transcode, it is user-local, not a system package from this repo.

**Smoke checklist (Mac):**

1. First launch shows the wizard
2. Skip Instant → editor works
3. “I already have models” folder picker + scan
4. Accept without a stock key → painted art, not cards-only unless paint fails
5. Voice chip can read `basic voice` when Kokoro and edge-tts are down

## Shared JSON

Keep these in lockstep when you change one side:

- `Sources/ReelForgeCore/Resources/caption-styles/catalog.json`
- `Sources/ReelForgeCore/Resources/models/manifest.json` ↔ `windows/reelforge/models/manifest.json`
- EDL: `Sources/ReelForgeCore/Edit/EditList.swift` ↔ `windows/reelforge/edl.py`

## CI (this repo)

```bash
swift test --package-path .
REELFORGE_SKIP_INFER=1 REELFORGE_SKIP_COMFY=1 REELFORGE_SKIP_ACE=1 \
  python3 -m unittest discover -s windows/tests -v
```

Never download weights. Never add torch/diffusers/edge-tts/pyttsx3/moviepy to `windows/requirements.txt`.

## Landing page

`site/index.html` is the sales page (Windows + Mac download, honest disk sizes, no fake checkout). Open it locally; it does not need a build step.
