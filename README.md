# ReelForge

A desktop app for people starting a YouTube channel. It does not compete with CapCut on a timeline. It competes on a **YouTube-ready package**: you approve the script, we render locally with YouTube-safe audio, and you leave with an upload pack — not just an MP4.

There is **no silent path** from topic to finished video. Draft → **Accept script** → compose/export. YouTube 2026 inauthentic-content review is at the channel level; firehose automation is a liability.

Faceless channels first. Shorts (9:16) and long-form (16:9).

Two clients, same product rules:

| App | Who it is for | How to run |
| --- | --- | --- |
| **macOS** (SwiftUI + AVFoundation) | Mac with Xcode | `xcodegen generate` then open `ReelForge.xcodeproj` |
| **Windows** (Python + ffmpeg) | Windows 10/11 test PCs | [`windows/README.md`](windows/README.md) — `python -m reelforge` |

Marketing site: [`site/index.html`](site/index.html)

**What we sell (core):** the editor, 30 caption styles, ffmpeg/AVFoundation, OFL fonts, Pexels/Pixabay, Kokoro or edge-tts, and the publish pack. It works with **zero** local diffusion models.

**Studio/Creator extra:** an in-app Model Manager. The user downloads or points at existing weights. ReelForge runs LTX and Qwen itself. We do not ship a node-graph sidecar or 80GB of weights.

## Windows (install and test today)

Python 3.12, Node is unused, ffmpeg on PATH. No Xcode.

```bat
cd windows
py -3.12 -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m reelforge
```

That opens a desktop window (pywebview). If WebView2 fails, it opens the local UI in your browser. Pick Viral Hook, type a topic, Draft, Accept. The MP4 lands in `%USERPROFILE%\Videos\ReelForge\`.

Windows TTS is Kokoro-FastAPI `:8880` if it is up, else **edge-tts**, else Windows SAPI (`pyttsx3`). Piper is not embedded. Stock is Pexels-first, Pixabay second; Unsplash is off. Music is a programmatic original-safe bed. Core ships with no diffusion weights.

## macOS requirements

- macOS 14+ (Apple Silicon first; Intel should work)
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Nothing optional is required to export a playable video. AVSpeech, styled cards, and bundled music beds always work.

## Open-source / free stack

| Job | Tool | License / notes | Required? |
| --- | --- | --- | --- |
| Script / SEO | Ollama at `localhost:11434` | Local LLM. Template writer if down. | Optional |
| TTS | **Kokoro-FastAPI** `http://127.0.0.1:8880/v1/audio/speech` | Apache 2.0, OpenAI-compatible. Named voices, per-project lock. | Optional |
| TTS | macOS `AVSpeechSynthesizer` | Always the fallback. Piper is **not** embedded (piper1-gpl is GPL-3.0). | Built-in |
| Voiceover | User-dropped WAV/M4A/MP3 | Wins over every TTS engine | Optional |
| Captions | Duration-align from script | Word-timed cards, karaoke / pop / lower-third | Built-in |
| Captions | Whisper HTTP at `:9000` / WhisperKit if present | Used only when a real VO file exists | Optional |
| Stock video | [Pexels Videos API](https://www.pexels.com/api/) | Free key. Settings / Keychain `REELFORGE_PEXELS_API_KEY` | Optional |
| Stock photo | Unsplash | **Off by default.** Manual Settings path only. Unsplash API terms: non-automated, must hotlink, cannot charge for API content. | Manual |
| Local image / video | In-app LTX / Qwen via official Python APIs | Optional Model Manager. User points at existing weights. Never bundled. | Optional |
| Music | Bundled original-safe beds + user folder | Duck **8–12 dB** under VO. Never CapCut/TikTok/copyrighted downloads. License ledger on the project. | Built-in |
| Compose / export | AVFoundation / VideoToolbox | H.264 MP4 to `~/Movies/ReelForge/<video-folder>/`. ffmpeg not vendored. | Built-in |
| YouTube upload | Data API key in Settings | Field stored. Upload button is disabled / coming soon. No fake upload | Optional |

Footage order per beat, never stall:

1. User local video / images
2. **Pexels Videos API** (`Authorization` header, `/videos/search`, page 2+ to skip first-page generic office/nature/city-aerial). Per-channel `video.id` blacklist. Pixabay second.
3. In-app LTX hook clip + Qwen stills (Ken Burns) if Model Manager marked those weights Ready
4. Unsplash stills only if you explicitly enable the manual toggle
5. Generated gradient / type cards — only if **cards ok**

Picture rules: first beat **must** be a hook (builder fails otherwise). First 1.5s = on-screen claim + VO start + picture change. No logo open. Captions stay in the Shorts safe zone (~15% top and bottom, right rail clear). Viral Hook is 3–6 words/line. Music ducks 8–12 dB. Thumbnails are 3–6 huge words. Title promise appears in title + thumb + first 3s VO.

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
- `⌘R` draft script / cancel
- `⌘↩` accept script (required before render)
- `⌘E` reveal the last export

Each export is a folder under `~/Movies/ReelForge/` containing the MP4, thumbnail `.jpg`, sidecar `.srt`, and publish-pack `.json`.

## Create → Generate → Publish pack

1. **Topic or full script** — a sentence, a list, or a pasted script.
2. **Channel type** — faceless facts, listicle, explainer, storytime, product, commentary, news.
3. **Target** — YouTube Short (15–60s) or Long (3–8 min) with duration control.
4. **Language** — English first; the model is ready for more.
5. **Series / pillar** — optional name used in titles and tags.
6. **Draft script** — Ollama or the template writer. Stops at the script desk.
7. **Accept script** — required. Edit hook, beats, and captions. No compose until this click.
8. **Publish pack** — title (≤70, same promise as thumb + first 3s VO), description hook in the first 150 characters, chapters from 0:00, tags, up to 3 thumbnails, SRT, asset credits, reminder to tick YouTube’s altered/synthetic content checkbox.

Batch (P2): paste topics, draft sequentially. **Each item still requires Accept script.** No auto-upload.

## Channel kit

Settings → Channel:

- Channel name, primary / accent colors
- Logo drop (watermark **after** the first 1.5s — never a logo-first open)
- Outro subscribe card (optional)
- Default voice, default preset, default aspect
- Imported music folder (bundled original-safe beds if empty)

Applied after you **Accept script**. No channel intro is prepended.

## Voice

Priority: dropped VO → **Kokoro-FastAPI** `http://127.0.0.1:8880/v1/audio/speech` → AVSpeech.

Named voices (Bella, Sarah, Adam, Michael, Emma, Nicole, Fenrir), per-project lock, pause at commas. Piper is **not** embedded (piper1-gpl is GPL-3.0) and is not on the synthesize path.

The inspector shows the live engine, a named voice picker, and speed.

## What works offline

Always:

- Template script + SEO writer (hook / body / CTA, title / description / tags / chapters)
- Storyboard timing from the preset pace
- System `AVSpeechSynthesizer` voiceover
- Word-timed caption cards + sidecar SRT
- Styled gradient / typography cards
- Programmatic original-safe music beds
- Color grade, Ken Burns, grain, transitions, optional subscribe outro
- H.264 MP4 + 1280×720 thumbnail via AVFoundation / Core Image

The director never stalls. If a source is missing it records a warning on the project and keeps going.

## Optional keys

**Pexels** (stock video, preferred over stills):

1. Create a free key at [pexels.com/api](https://www.pexels.com/api/).
2. Paste it in Settings, or set `REELFORGE_PEXELS_API_KEY`.

**Unsplash** (manual stills only, **off by default**):

Unsplash API terms forbid automated pipelines, require hotlinking, and do not allow charging for API content. Keep the Settings toggle off. Do not use Unsplash on the automated Generate path.

**YouTube Data API** (upload later):

- Settings stores the key. The Upload button stays disabled until OAuth is wired. ReelForge will not pretend an upload succeeded.

Do not put keys in the repo. `.env` is gitignored.

## Optional local services

```bash
# Script / SEO
brew install ollama
ollama serve
ollama pull llama3.2

# Voice (preferred)
# Kokoro-FastAPI listens on http://127.0.0.1:8880
# POST /v1/audio/speech  (OpenAI-compatible, Apache-2.0)
```

**Model Manager** (Creator/Studio, optional): on first launch ReelForge scans folders you already have (`modelsDir`, plus common weight locations). If `ltx-2.3-22b-distilled.safetensors` or `qwen-image` is found, that slot is **Ready** with no download. Inference uses official Python APIs (`ltx-pipelines` DistilledPipeline and/or `diffusers.LTX2Pipeline` / `diffusers.QwenImagePipeline`). One pipeline at a time. Core works with **zero** local diffusion models. Weights are never bundled and never downloaded in CI.

Music is **bundled original-safe beds** plus a user-imported folder. ACE-Step is not on the Director path. Never download CapCut, TikTok, or copyrighted tracks.

## Architecture

The edit is a **JSON storyboard plus a deterministic AVFoundation renderer**. An LLM never moves frames.

1. **Draft script** — user script, Ollama, or the template writer. Stops here.
2. **Accept script** — required human gate. Edit hook, beats, and captions. No silent path to MP4.
3. **Storyboard** — JSON beats. First beat **must** be a hook (≥1.5s). Builder fails on greeting / logo opens. Optional outro only.
4. **Voice** — dropped VO, Kokoro-FastAPI (`:8880/v1/audio/speech`), then Mac AVSpeech or Windows SAPI. Per-project lock. Pauses at commas.
5. **Captions** — 3–6 words on Viral Hook; Shorts ~15% top/bottom + right rail clear; karaoke/pop; SRT.
6. **Footage** — local → Pexels / Pixabay → in-app LTX hook + Qwen stills if Ready → cards only if `allowCards`. Unsplash off.
7. **Music** — bundled original-safe bed or imported folder. Duck 8–12 dB under VO. License ledger on the project.
8. **Compose** — per-beat H.264 clips (Ken Burns, grade, captions, logo after 1.5s). Mac: AVFoundation / VideoToolbox. Windows: ffmpeg (not vendored).
9. **Package + export** — title ≤70, description hook in first 150 chars, chapters from 0:00, tags, 1–3 thumbs, credits, synthetic-content reminder. No auto-upload.

```
Sources/ReelForgeCore/     SPM library, Linux-testable
Sources/ReelForgeApp/      SwiftUI + AVFoundation Mac app
Tests/ReelForgeTests/      storyboard, captions, presets, publish pack
windows/                   Python desktop app (FastAPI + pywebview + ffmpeg)
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
cd windows && python -m unittest discover -s tests -v
```

CI runs the Swift job. It does **not** compile the SwiftUI/AVFoundation target. Windows unit tests cover storyboard hook + caption split + publish pack.

On a Mac, after `xcodegen generate`, build the **ReelForge** scheme in Xcode.

## Example

1. Select **Listicle** (or Viral Hook)
2. Type `3 reasons your morning walk beats the gym`
3. **Draft script**
4. Edit the desk if you want, then **Accept script**
5. Play the MP4, copy the Publish pack, reveal the folder

You get speech, captions, B-roll or styled cards, a ducked bed, a thumbnail, sidecar SRT, and asset credits.

## Notes

- Music beds are synthesized at export time, or copied from your imported folder. No CapCut / TikTok / copyrighted audio is downloaded.
- App Sandbox is on, with Movies write, user-selected files, and outgoing network.
- Do not put API keys in the repo.
- We do not ship doctor, lawyer, finance-advisor, or political-expert impersonation presets.
