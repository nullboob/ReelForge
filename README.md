# ReelForge

A native macOS app for people starting a YouTube channel. Type a topic, pick a preset, hit **Generate**. ReelForge writes the script, speaks it, burns captions, lays B-roll, ducks music, and hands you a publish-ready MP4 plus a **Publish pack** (title, description, tags, chapters, thumbnail, SRT).

This is an automated director, not a timeline NLE. There is no manual cutting. Faceless channels first. Shorts (9:16) and long-form (16:9).

Marketing site: [`site/index.html`](site/index.html)

## Requirements

- macOS 14+ (Apple Silicon first; Intel should work)
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Nothing optional is required to export a playable video. AVSpeech, styled cards, and bundled music beds always work.

## Open-source / free stack

| Job | Tool | License / notes | Required? |
| --- | --- | --- | --- |
| Script / SEO | Ollama at `localhost:11434` | Local LLM. Template writer if down. | Optional |
| TTS | **Kokoro-82M** via `http://127.0.0.1:8880` (kokoro-fastapi) | Apache 2.0. Voice picker. | Optional |
| TTS | **Piper** binary on `PATH` | CPU, offline | Optional |
| TTS | macOS `AVSpeechSynthesizer` | Always works so Generate never blocks | Built-in |
| Voiceover | User-dropped WAV/M4A/MP3 | Wins over every TTS engine | Optional |
| Captions | Duration-align from script | Word-timed cards, karaoke / pop / lower-third | Built-in |
| Captions | Whisper HTTP at `:9000` / WhisperKit if present | Used only when a real VO file exists | Optional |
| Stock video | [Pexels Videos API](https://www.pexels.com/api/) | Free key. Settings / Keychain `REELFORGE_PEXELS_API_KEY` | Optional |
| Stock photo | [Unsplash API](https://unsplash.com/developers) | Free key. Settings / Keychain `REELFORGE_UNSPLASH_ACCESS_KEY` | Optional |
| Local image / video | ComfyUI `:8188`, A1111 `:7860` | User already runs these. LTX if a workflow is available | Optional |
| Music | Bundled original-safe beds | Pulse / cinematic / clean / warm, ducked under VO | Built-in |
| Music | ACE-Step HTTP (`7865` / `8001` / `8019`) | Optional hook. No copyrighted downloads | Optional |
| Compose / export | AVFoundation | H.264 MP4 to `~/Movies/ReelForge/<video-folder>/` | Built-in |
| Export fallback | `ffmpeg` on PATH | Only if `AVAssetExportSession` fails | Optional |
| YouTube upload | Data API key in Settings | Field stored. Upload button is disabled / coming soon. No fake upload | Optional |

Footage order per beat, never stall:

1. User local video / images
2. Pexels Videos API
3. Unsplash stills + Ken Burns
4. ComfyUI localhost:8188
5. Generated gradient / type cards

Attribution (Pexels / Unsplash) is stored on `project.json`. It is not burned into the frame.

## Generate the Xcode project and run

```bash
brew install xcodegen
git clone https://github.com/nullboob/ReelForge.git
cd ReelForge
xcodegen generate
open ReelForge.xcodeproj
```

In Xcode, select the **ReelForge** scheme and run. Minimum window size is 1200×800.

Keyboard:

- `⌘N` new project
- `⌘R` generate / cancel
- `⌘E` reveal the last export

Each export is a folder under `~/Movies/ReelForge/` containing the MP4, thumbnail `.jpg`, sidecar `.srt`, and publish-pack `.json`.

## Create → Generate → Publish pack

1. **Topic or full script** — a sentence, a list, or a pasted script.
2. **Channel type** — faceless facts, listicle, explainer, storytime, product, commentary, news.
3. **Target** — YouTube Short (15–60s) or Long (3–8 min) with duration control.
4. **Language** — English first; the model is ready for more.
5. **Series / pillar** — optional name used in titles and tags.
6. **Generate** — voice, captions, footage, music, compose, package, export.
7. **Publish pack** — title (≤70), description with chapters + CTA, tags / hashtags, 1280×720 thumbnail, suggested filename.

Batch: paste two or more topics, pick a preset, **Generate all**. Progress list. One export folder per video.

## Channel kit

Settings → Channel:

- Channel name, primary / accent colors
- Logo drop (safe-area watermark)
- Intro seconds (0–3) and outro subscribe card
- Default voice, default preset, default aspect

Applied automatically on Generate.

## Voice

Priority: dropped VO → Kokoro-82M (`:8880`) → Piper on PATH → AVSpeech.

The inspector shows the live engine, a named voice picker, speed, and pause between beats.

## What works offline

Always:

- Template script + SEO writer (hook / body / CTA, title / description / tags / chapters)
- Storyboard timing from the preset pace
- System `AVSpeechSynthesizer` voiceover
- Word-timed caption cards + sidecar SRT
- Styled gradient / typography cards
- Programmatic original-safe music beds
- Color grade, Ken Burns, grain, transitions, channel intro/outro
- H.264 MP4 + 1280×720 thumbnail via AVFoundation / Core Image

The director never stalls. If a source is missing it records a warning on the project and keeps going.

## Optional keys

**Pexels** (stock video, preferred over stills):

1. Create a free key at [pexels.com/api](https://www.pexels.com/api/).
2. Paste it in Settings, or set `REELFORGE_PEXELS_API_KEY`.

**Unsplash** (stills + Ken Burns):

1. Create an access key at [unsplash.com/developers](https://unsplash.com/developers).
2. Paste it in Settings, or set `REELFORGE_UNSPLASH_ACCESS_KEY`.

**YouTube Data API** (upload later):

- Settings stores the key. The Upload button stays disabled until OAuth is wired. ReelForge will not pretend an upload succeeded.

Do not put keys in the repo. `.env` is gitignored.

## Optional local services

```bash
# Script / SEO
brew install ollama
ollama serve
ollama pull llama3.2

# Voice (pick one)
# Kokoro-fastapi commonly listens on http://127.0.0.1:8880
# Piper: brew install piper-tts   # if a bottle exists on your Mac
```

ComfyUI on `http://127.0.0.1:8188` is probed first for local images / LTX video. Export API-format workflows to:

```
~/Library/Application Support/ReelForge/comfy-t2i.json
~/Library/Application Support/ReelForge/comfy-i2v.json
```

Automatic1111 on `7860` is a secondary image API. ACE-Step is optional music only.

## Architecture

The edit is a **JSON storyboard plus a deterministic AVFoundation renderer**. An LLM never moves frames.

1. **Script** — user script, Ollama, or the template writer
2. **Storyboard** — beats clamped to the preset cut range, plus channel intro/outro
3. **Voice** — dropped VO, Kokoro, Piper, or AVSpeech (always produces audio)
4. **Captions** — word-timed cards; optional local Whisper HTTP; burn-in and/or SRT
5. **Footage** — local → Pexels → Unsplash → ComfyUI / A1111 → styled cards
6. **Music** — ACE-Step if a clean hook answers, else a synthesized loop, ducked under VO
7. **Compose** — per-beat H.264 clips (Ken Burns, grade, captions, logo) assembled with `AVMutableComposition`
8. **Package** — title, description, tags, chapters, 1280×720 thumbnail
9. **Export** — `AVAssetExportSession` into a per-video folder; `ffmpeg` only if that fails

```
Sources/ReelForgeCore/     SPM library, Linux-testable
Sources/ReelForgeApp/      SwiftUI + AVFoundation Mac app
Tests/ReelForgeTests/      storyboard, captions, presets, publish pack
site/                      sales page
```

Projects persist under `~/Library/Application Support/ReelForge/Projects/<id>/`. Channel kit is `channel.json` next to that.

## Presets

Original eight, plus six YouTube starters:

| Preset | Aspect | Length | Feel |
| --- | --- | --- | --- |
| **Viral Hook** | 9:16 | 15s | Punchy captions, 0.8–1.4s hard cuts |
| **Cinematic Story** | 9:16 | 45s | Slow Ken Burns, film grade, fades |
| **Product Demo** | 16:9 | 30s | Clean feature beats |
| **Faceless Facts** | 9:16 | 20s | Bold type, stock-style B-roll |
| **Luxury Brand** | 9:16 | 30s | High contrast, sparse type |
| **YouTube Short News** | 9:16 | 30s | Lower-third / karaoke captions |
| **Travel Vlog** | 9:16 | 30s | Warm grade, whip pans |
| **Tutorial Steps** | 9:16 | 45s | Numbered cards, calm fades |
| **Listicle** | 9:16 | 45s | Numbered payoffs |
| **Explainer** | 16:9 | 3 min | Calm cuts, one idea |
| **Storytime** | 9:16 | 60s | Quiet open, a turn |
| **Motivational** | 9:16 | 30s | Commentary energy |
| **Podcast Clip** | 9:16 | 45s | Big karaoke captions |
| **News Roundup** | 16:9 | 3 min | Lower-thirds, no fluff |

JSON lives in `Sources/ReelForgeCore/Resources/presets/`.

## Tests (portable)

On Linux or macOS, without the Mac SDK:

```bash
swift test
```

CI runs that job. It does **not** compile the SwiftUI/AVFoundation target.

On a Mac, after `xcodegen generate`, build the **ReelForge** scheme in Xcode.

## Example

1. Select **Listicle** (or Viral Hook)
2. Type `3 reasons your morning walk beats the gym`
3. Generate
4. Play the MP4, copy the Publish pack, reveal the folder

You get speech, captions, B-roll or styled cards, a ducked bed, a thumbnail, and sidecar SRT.

## Notes

- Music beds are synthesized at export time unless a local ACE-Step `/generate` hook answers. No copyrighted audio is downloaded.
- App Sandbox is on, with Movies write, user-selected files, and outgoing network.
- Do not put API keys in the repo.
