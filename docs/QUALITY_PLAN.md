# ReelForge quality bar

Exports should be uploadable as a finished Short with no rework. A pink-to-black type card that says “Stop scrolling…” in white Arial is never the default finished look.

## What this pass shipped

- Shared 30-style research catalog at `Sources/ReelForgeCore/Resources/caption-styles/catalog.json`. Old IDs alias (e.g. `dynamic-minimal` → `tiktok-classic-outline`).
- Bundled OFL/Apache fonts in `Sources/ReelForgeCore/Resources/fonts/` (Montserrat ExtraBold, Anton, Bebas Neue, Archivo Black, Oswald, Open Sans, Inter, Poppins, Roboto).
- Windows burn-in uses ffmpeg `-vf ass=` only (never `subtitles=` or `drawtext`). Karaoke is `\k` snap and `\kf` fill. PrimaryColour=highlight, SecondaryColour=base.
- PIL PNG overlay for multi-stop gradients, chrome/metal/fire/ice/candy, rounded pills, 3D stacks, bar wipes. Gradients are hook/accent only — default body is white + black stroke karaoke.
- Mac writes the same `.ass` for karaoke parity. CAGradientLayer is not used for 3+ stop fills.
- Mac SwiftUI picker uses the same catalog. ClipWriter karaoke / pop / plates honor the selected look.
- Voice order: Kokoro-FastAPI `http://127.0.0.1:8880/v1/audio/speech`, then edge-tts (Microsoft neural), then system TTS. Piper is not embedded.
- Stock: Pexels video first, Pixabay second. Cards are last-resort. Cards-only export is blocked unless the user opts into **cards ok**.
- Ken Burns on stills, gentle zoom pulse on video, eq/vignette grade, optional grain.
- Export target: 1080×1920 (or preset aspect), 30 fps, libx264 CRF 18, yuv420p, AAC 192k, music ducked 8–12 dB under VO.
- Caption block on 1080×1920 sits in y 700–1360 (above TikTok/Shorts UI). Word clock: 1–3 words or ≤2.0s per card, one emphasis word.
- Captions **replace**, never stack. ASS/PNG windows are exclusive. The hook beat is one clean card for the full hold (≥1.5s).
- Cards and stock **cover** 1080×1920 (scale+crop, `setsar=1`). No letterbox bars. A render with overlapping captions or black bars is not done.
- Footage ladder: local files → Pexels / Pixabay → in-app LTX hook + Qwen stills (if Model Manager marked them Ready) → cards only if `allowCards`.
- Inference is in-process via official Python APIs. The sold UI does not mention or require a node-graph sidecar. Hidden `REELFORGE_COMFY_URL` is an engineer hatch only. CI never downloads weights.

## The 30 styles

ASS-first: `tiktok-classic-outline`, `hormozi-yellow-pop`, `karaoke-yellow-sweep`, `word-pop-sync`, `single-word-center`, `bounce-fitness`, `typewriter-story`, `quiet-aesthetic-min`, `color-switch-strobe`, `commentary-telegraph`, `kinetic-hook-slide`, `neon-glow-pulse`, `outline-double-stroke`, `faceless-stack-highlight`, `podcast-split-karaoke`, `cinematic-gold-fade`.

PIL-first: `boxed-pill-yellow`, `beast-3d-pop`, `listicle-number-chip`, `boxed-kinetic-bar`, `cta-urgent-red`, plus the nine Premiere/AE gradients (`gradient-rainbow-word` … `gradient-duotone-yellow-pink`).

Viral Hook defaults to **tiktok-classic-outline** (white + black stroke karaoke). `dynamic-minimal` still resolves.

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