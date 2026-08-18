# ReelForge

A native macOS app that writes the edit for you. Pick a preset, type a topic or script, optionally drop local footage or a voiceover, and hit **Generate**. ReelForge builds a finished H.264 MP4 with captions, B-roll or styled cards, color grade, transitions, and a ducked music bed.

This is an automated director, not a timeline NLE. There is no manual cutting.

## Requirements

- macOS 14+ (Apple Silicon first; Intel should work)
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Optional:

- An [Unsplash](https://unsplash.com/developers) access key for still B-roll
- [Ollama](https://ollama.com) on `localhost:11434` for script writing
- **ComfyUI** on `http://127.0.0.1:8188` (probed first) for local image / LTX video
- Automatic1111 on `127.0.0.1:7860` as a secondary image backend
- ACE-Step on `127.0.0.1:7865` (optional music; programmatic beds always work)
- `ffmpeg` on `PATH` as an export fallback only. AVFoundation is the Mac export path.

Nothing optional is required to export a playable video.

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

Exports land in `~/Movies/ReelForge/`.

## What works offline

Always:

- Template script writer (hook / body / CTA from the topic)
- Storyboard timing from the preset pace
- System `AVSpeechSynthesizer` voiceover
- Word-timed caption cards burned into the picture
- Styled gradient/typography cards when no footage is available
- Programmatic original-safe music beds (pulse / cinematic / clean / warm)
- Color grade, Ken Burns, grain, transitions
- H.264 MP4 export via AVFoundation

Needs a key or a local service:

| Capability | Offline | Needs |
| --- | --- | --- |
| Unsplash stills | Styled cards | `REELFORGE_UNSPLASH_ACCESS_KEY` or Settings → Keychain |
| LLM script | Built-in writer | Ollama at `http://127.0.0.1:11434` |
| AI images | Styled cards | **ComfyUI `:8188` first**, then A1111 `:7860` |
| AI video | Skipped | Live ComfyUI + LTX nodes or `comfy-i2v.json`. No cloud video model is pretended. |
| Music | Programmatic bed | Optional ACE-Step HTTP if a `/generate` hook answers |
| Whisper word times | Duration alignment | Optional `http://127.0.0.1:9000/asr` |

The director never stalls. If a source is missing it records a warning on the project and keeps going.

## Unsplash

1. Create a developer app at [unsplash.com/developers](https://unsplash.com/developers) and copy the **Access Key**.
2. Either:
   - export `REELFORGE_UNSPLASH_ACCESS_KEY=...` in the environment Xcode / Terminal uses, or
   - paste it in **Settings** (stored in Keychain, never committed).
3. Photographer names are stored on `project.json`. They are not burned into the frame.

Without a key, Generate still works.

## Optional Ollama

```bash
brew install ollama
ollama serve
ollama pull llama3.2
```

ReelForge probes `http://127.0.0.1:11434/api/tags` and uses the first suitable model. If Ollama is down, the template writer produces a real script from the topic.

## Local ComfyUI (preferred image / video backend)

The Mac app talks to whatever is listening on this machine. A Windows portable ComfyUI + NVIDIA box on the LAN is fine if you port-forward `8188` to localhost, but ReelForge itself stays a native SwiftUI macOS app.

Probe order:

1. `GET http://127.0.0.1:8188/system_stats` then `/object_info`
2. If `CheckpointLoaderSimple` + KSampler exist, queue a simple text-to-image graph via `POST /prompt`
3. If LTX / I2V nodes are installed (`LTXV*`, `ltx-video-2b`, GGUF loaders, qwen-image-edit), Settings shows a video chip
4. To actually run *your* LTX or qwen-image-edit graph, export **API format** from ComfyUI and save:

```
~/Library/Application Support/ReelForge/comfy-t2i.json
~/Library/Application Support/ReelForge/comfy-i2v.json
```

ReelForge injects the beat prompt (and a start frame when I2V). If the exact workflow is missing, it skips video and keeps exporting with stills, Unsplash, or styled cards.

Automatic1111 on `7860` is still probed as a fallback image API.

## Optional ACE-Step

Programmatic original-safe beds always play. If ACE-Step is up on `7865` / `8001` / `8019` and exposes a simple `/generate` JSON hook, the Director will try it once. Copyrighted music is never downloaded.

## Architecture

The edit is a **JSON storyboard plus a deterministic AVFoundation renderer**. An LLM never moves frames.

1. **Script** — user script, Ollama, or the template writer
2. **Storyboard** — beats clamped to the preset cut range
3. **Voice** — dropped VO or `AVSpeechSynthesizer` (always produces audio)
4. **Captions** — word-timed cards; optional local Whisper HTTP
5. **Footage** — local files → ComfyUI (8188) / A1111 → Unsplash → styled cards
6. **Music** — ACE-Step if a clean hook answers, else a synthesized loop, ducked under VO
7. **Compose** — per-beat H.264 clips (Ken Burns, grade, burned captions) assembled with `AVMutableComposition` + `AVMutableVideoComposition`
8. **Export** — `AVAssetExportSession` to `~/Movies/ReelForge/`; `ffmpeg` only if that fails

Portable logic lives in `Sources/ReelForgeCore` (models, script, storyboard, captions, music, timeline plan). The Mac app in `Sources/ReelForgeApp` owns SwiftUI, AVFoundation, Unsplash, and local HTTP.

```
Sources/ReelForgeCore/     SPM library, Linux-testable
Sources/ReelForgeApp/      SwiftUI + AVFoundation Mac app
Tests/ReelForgeTests/      storyboard timing, caption split, presets, timeline
```

Projects persist under `~/Library/Application Support/ReelForge/Projects/<id>/`.

## Presets

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

JSON lives in `Sources/ReelForgeCore/Resources/presets/`.

## Tests (portable)

On Linux or macOS, without the Mac SDK:

```bash
swift test
```

CI runs that job. It does **not** compile the SwiftUI/AVFoundation target.

On a Mac, after `xcodegen generate`, build the **ReelForge** scheme in Xcode.

## Example

1. Select **Viral Hook**
2. Type `3 reasons your morning walk beats the gym`
3. Generate
4. Play the MP4 and use **Reveal in Finder**

You get speech, captions, B-roll or styled cards, a pulse bed, and a file in `~/Movies/ReelForge/`.

## Notes

- Music beds are synthesized at export time unless a local ACE-Step `/generate` hook answers. No copyrighted audio is downloaded.
- App Sandbox is on, with Movies write, user-selected files, and outgoing network.
- Do not put Unsplash keys in the repo. `.env` is gitignored.
