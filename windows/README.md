# ReelForge for Windows

Same product as the Mac app: you draft a script, click **Accept**, then we render a YouTube-ready pack on this PC. Not a timeline editor. Not a silent topic→MP4 firehose.

Requires Windows 10/11, Python 3.12, and `ffmpeg` on PATH (x264).

## Install and run

From the repo root, or from this folder:

```bat
cd windows
py -3.12 -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m reelforge
```

That command opens a **desktop window** (pywebview). If WebView2/pywebview fails, it opens `http://127.0.0.1:8765` in your default browser and keeps the server running.

## First video

1. Pick **Viral Hook**
2. Type `3 reasons your morning walk beats the gym`
3. **Draft script**
4. Edit the desk if you want, then **Accept script**
5. Play the MP4, copy the publish pack, **Export** to reveal the folder in Explorer

Exports land in `%USERPROFILE%\Videos\ReelForge\<timestamp-slug>\` as MP4 + thumbnail + SRT + JSON + `credits.json`.

## Optional

| Job | Where |
| --- | --- |
| Better TTS | Kokoro-FastAPI at `http://127.0.0.1:8880/v1/audio/speech` |
| Scripts | Ollama at `localhost:11434` |
| Stock B-roll | Pexels key in Settings (`Authorization` header) |

Fallback TTS is Windows SAPI via `pyttsx3`. Piper is **not** embedded. Unsplash is off. Music is a programmatic original-safe bed or a folder you import. Duck 8–12 dB under VO.

## Tests (portable)

```bat
cd windows
.venv\Scripts\python -m unittest discover -s tests -v
```

Storyboard hook + caption split + publish pack do not need ffmpeg.
