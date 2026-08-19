# ReelForge quality bar

Exports should be uploadable as a finished Short with no rework. A pink-to-black type card that says “Stop scrolling…” in white Arial is never the default finished look.

## What this pass shipped

- Shared 30-style catalog at `Sources/ReelForgeCore/Resources/caption-styles/catalog.json`.
- Bundled OFL/Apache fonts in `Sources/ReelForgeCore/Resources/fonts/` (Montserrat ExtraBold, Anton, Bebas Neue, Archivo Black, Oswald, Open Sans, Inter, Poppins, Roboto).
- Windows burn-in uses ffmpeg `ass=` with `\k` / `\kf` karaoke, or Pillow RGBA plates for gradients and pills.
- Mac SwiftUI picker uses the same catalog. ClipWriter karaoke / pop / plates honor the selected look.
- Voice order: Kokoro-FastAPI `http://127.0.0.1:8880/v1/audio/speech`, then edge-tts (Microsoft neural), then system TTS. Piper is not embedded.
- Stock: Pexels video first, Pixabay second. Cards are last-resort. Cards-only export is blocked unless the user opts into **cards ok**.
- Ken Burns on stills, gentle zoom pulse on video, eq/vignette grade, optional grain.
- Export target: 1080×1920 (or preset aspect), 30 fps, libx264 CRF 18, yuv420p, AAC 192k, music ducked 8–12 dB under VO.
- Caption safe area: below the top ~12% and above the bottom ~18%, plus the 9:16 right rail.
- Captions **replace**, never stack. ASS/PNG windows are exclusive. The hook beat is one clean card for the full hold (≥1.5s).
- Cards and stock **cover** 1080×1920 (scale+crop, `setsar=1`). No letterbox bars. A render with overlapping captions or black bars is not done.
- Footage ladder: local files → Pexels / Pixabay → in-app LTX hook + Qwen stills (if Model Manager marked them Ready) → cards only if `allowCards`.
- Inference is in-process via official Python APIs. The sold UI does not mention or require a node-graph sidecar. Hidden `REELFORGE_COMFY_URL` is an engineer hatch only. CI never downloads weights.

## The 30 styles

CapCut / 2026 short-form: `dynamic-minimal`, `hormozi-classic`, `pill-black`, `pill-yellow`, `pill-hot`, `pill-brand`, `capcut-classic`, `most-readable`, `fancy-soft`, `checksub-rose`, `glow-clean`, `boxed-outline`, `typewriter`, `color-switch`, `quiet-aesthetic`, `bebas-sports`, `archivo-hype`, `tiktok-native`.

Premiere / AE gradients: `sunset-fill`, `candy-pop`, `neon-cyber`, `gold-metallic`, `fire-sweep`, `ice-chrome`, `rainbow-word`, `duotone-sun`, `chrome-silver`, `ocean-teal`, `grape-aurora`, `lime-punch`.

Viral Hook defaults to **dynamic-minimal** (white karaoke, no yellow). Hormozi Classic stays a named option.

## Still needs a live machine

These paths are implemented but cannot be proven from Linux CI:

- Real Pexels / Pixabay downloads with API keys on Windows or Mac.
- In-app LTX / Qwen on a machine that already has Ready weights (never downloaded here).
- Kokoro-FastAPI word-timed speech at `:8880`.
- edge-tts on a machine that can reach Microsoft’s neural endpoint (then ffmpeg transcode to WAV).
- Mac app compile / AVFoundation export (this environment is Linux; do not treat `swift test` as a Mac build).
- Visual A/B of karaoke vs a CapCut reference on a phone.

After `git pull` on Windows:

```bat
cd windows
py -3.12 -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m reelforge
```

Add a Pexels key (and optional Pixabay key) in Settings before Accept. Leave **cards ok** unchecked unless you really want a slide deck.