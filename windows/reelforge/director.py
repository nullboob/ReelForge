from __future__ import annotations

import json
import threading
from datetime import datetime
from pathlib import Path
from typing import Any
from uuid import uuid4

import httpx

from reelforge import captions as captionlib
from reelforge import footage
from reelforge import music
from reelforge import niche
from reelforge import presets as presetlib
from reelforge import publish
from reelforge import renderer
from reelforge import script as scriptlib
from reelforge import settings_store
from reelforge import speech
from reelforge import storyboard as boardlib
from reelforge.hooks import is_forbidden_open
from reelforge import caption_styles
from reelforge.paths import videos_dir, work_dir
class Director:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.progress: dict[str, Any] = {"detail": "Type a topic, then accept the script before we render.", "fraction": 0, "busy": False}
        self.project: dict[str, Any] = self._empty_project()
        self.pending: dict[str, Any] | None = None

    def _empty_project(self) -> dict[str, Any]:
        return {
            "id": str(uuid4()),
            "topic": "",
            "presetID": "viral-hook",
            "script": None,
            "storyboard": None,
            "captions": [],
            "scriptAccepted": False,
            "warnings": [],
            "publishPack": None,
            "exportPath": None,
            "ttsEngine": None,
            "licenseLedger": [],
        }

    def status(self) -> dict[str, Any]:
        settings = settings_store.load()
        from reelforge import comfy
        from reelforge import models
        catalog = models.scan(settings.get("modelsDir") or None)
        comfy_status = comfy.probe(settings.get("comfyUrl"))
        return {
            "kokoro": speech.probe_kokoro(),
            "ollama": speech.probe_ollama(),
            "ffmpeg": bool(__import__("reelforge.ffmpeg_bundle", fromlist=["which_ffmpeg"]).which_ffmpeg()),
            "pexels": bool(settings.get("pexelsKey")),
            "ttsEngine": "Kokoro" if speech.probe_kokoro() else ("edge-tts-cli" if speech.probe_edge_tts_cli() else ("basic voice" if speech.probe_basic_voice() else "no VO")),
            "setupComplete": bool(settings.get("setupComplete")),
            "pixabay": bool(settings.get("pixabayKey")),
            "stockReady": bool(settings.get("pexelsKey") or settings.get("pixabayKey")),
            "captionStyles": caption_styles.all_styles(),
            "voices": [{"id": vid, "name": name} for vid, name in speech.KOKORO_VOICES],
            "models": catalog,
            "videoReady": catalog.get("videoReady"),
            "imageReady": catalog.get("imageReady"),
            "anyReady": catalog.get("anyReady"),
            "comfy": comfy_status,
            "comfyUrl": settings.get("comfyUrl") or comfy.DEFAULT_URL,
            "localMode": settings.get("localMode") or "stock-first",
            "aceStep": music.probe_ace(),
        }

    def new_project(self) -> dict[str, Any]:
        with self.lock:
            self.project = self._empty_project()
            self.pending = None
            self.progress = {"detail": "Type a topic, then accept the script before we render.", "fraction": 0, "busy": False}
            return self.snapshot()

    def snapshot(self) -> dict[str, Any]:
        return {
            "project": self.project,
            "progress": self.progress,
            "awaitingAccept": bool(self.pending) and not self.project.get("scriptAccepted"),
            "settings": settings_store.load(),
        }

    def draft(self, payload: dict[str, Any]) -> dict[str, Any]:
        topic = (payload.get("topic") or "").strip()
        if not topic:
            raise ValueError("Type a topic first.")
        blocked = niche.warning_for(topic)
        if blocked:
            raise ValueError(blocked)
        preset = presetlib.get_preset(payload.get("presetID") or "viral-hook")
        duration = int(payload.get("duration") or preset.get("durationSec") or 15)
        style_id = payload.get("captionStyleID") or settings_store.load().get("captionStyleID") or caption_styles.default_for_preset(preset["id"])
        settings = settings_store.save({
            "usePexels": payload.get("usePexels", True),
            "usePixabay": payload.get("usePixabay", True),
            "useUnsplash": bool(payload.get("useUnsplash")),
            "useLocalAI": payload.get("useLocalAI", True),
            "useLocalModels": payload.get("useLocalModels", settings_store.load().get("useLocalModels", True)),
            "localMode": payload.get("localMode") or settings_store.load().get("localMode") or "stock-first",
            "voiceIdentifier": payload.get("voiceIdentifier"),
            "captionStyleID": style_id,
            "allowCards": bool(payload.get("allowCards")),
        })
        channel = settings.get("channel") or {}
        self._emit("Writing hook, body, and CTA", 0.08)
        warnings: list[str] = []
        if scriptlib.looks_like_full_script(topic):
            script = scriptlib.parse_user_script(topic)
        elif payload.get("useLocalAI", settings.get("useLocalAI", True)):
            script, ollama_note = self._try_ollama(topic, preset, duration)
            if ollama_note:
                warnings.append(ollama_note)
        else:
            script = scriptlib.write(topic, preset["id"], duration)
        if is_forbidden_open(script["hook"]):
            script["hook"] = scriptlib.write(topic, preset["id"], duration)["hook"]
            warnings.append("Replaced a greeting / lecture open with a hook claim.")
        board = boardlib.build(script, preset, duration)
        board = boardlib.appending_outro(board, channel.get("name") or "", bool(channel.get("outroEnabled", True)))
        cues = captionlib.cues_for_preset(script, board, preset)
        project = self._empty_project()
        project.update({
            "topic": topic,
            "presetID": preset["id"],
            "script": script,
            "storyboard": board,
            "captions": cues,
            "warnings": warnings,
            "scriptAccepted": False,
            "duration": duration,
            "aspect": payload.get("aspect") or preset.get("aspect"),
            "target": payload.get("target") or "short",
            "seriesName": payload.get("seriesName") or None,
            "voiceIdentifier": payload.get("voiceIdentifier") or settings.get("voiceIdentifier"),
            "captionStyleID": style_id,
            "allowCards": bool(payload.get("allowCards") or settings.get("allowCards")),
            "cardsOnly": False,
        })
        with self.lock:
            self.project = project
            self.pending = {"preset": preset, "settings": settings, "payload": payload}
            self.progress = {
                "detail": "Accept the script to render. Nothing exports until you click Accept.",
                "fraction": 0.28,
                "busy": False,
                "step": "review",
            }
        return self.snapshot()

    def accept(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self.lock:
            pending = self.pending
            if not pending:
                raise ValueError("Draft a script first.")
        hook = (payload.get("hook") or self.project.get("script", {}).get("hook") or "").strip()
        body = payload.get("body") or self.project.get("script", {}).get("body") or []
        cta = (payload.get("cta") or self.project.get("script", {}).get("cta") or "").strip()
        blocked = niche.warning_for(f"{hook} {self.project.get('topic', '')}")
        if blocked:
            raise ValueError(blocked)
        if is_forbidden_open(hook):
            raise boardlib.StoryboardError()
        script = {"hook": hook, "body": [line for line in body if str(line).strip()], "cta": cta, "source": "user"}
        preset = pending["preset"]
        duration = float(self.project.get("duration") or preset.get("durationSec") or 15)
        board = boardlib.build(script, preset, duration)
        settings = pending["settings"]
        channel = settings.get("channel") or {}
        board = boardlib.appending_outro(board, channel.get("name") or "", bool(channel.get("outroEnabled", True)))
        edited = payload.get("captions")
        cues = self.project.get("captions") or []
        if edited and len(edited) == len(cues):
            for index, text in enumerate(edited):
                cues[index]["text"] = text
        elif not cues:
            cues = captionlib.cues_for_preset(script, board, preset)
        style_id = payload.get("captionStyleID") or settings.get("captionStyleID") or caption_styles.default_for_preset(preset["id"])
        settings_store.save({"captionStyleID": style_id, "allowCards": bool(payload.get("allowCards") or settings.get("allowCards"))})
        self.project["captionStyleID"] = style_id
        self.project["allowCards"] = bool(payload.get("allowCards") or settings.get("allowCards"))
        self.project["script"] = script
        self.project["storyboard"] = board
        self.project["captions"] = cues
        self.project["scriptAccepted"] = True
        try:
            return self._compose(script, board, cues, preset, settings, {**(pending.get("payload") or {}), **payload})
        except Exception as exc:
            from reelforge.errors import human, log
            message = human(exc)
            log(f"accept failed: {exc}")
            self.progress = {"detail": message, "fraction": 0.4, "busy": False, "failed": True}
            raise RuntimeError(message) from exc

    def _compose(
        self,
        script: dict[str, Any],
        board: dict[str, Any],
        cues: list[dict[str, Any]],
        preset: dict[str, Any],
        settings: dict[str, Any],
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        channel = settings.get("channel") or {}
        work = work_dir() / self.project["id"]
        work.mkdir(parents=True, exist_ok=True)
        self._emit("Kokoro-class VO (never SAPI)", 0.35)
        spoken = " ".join(scriptlib.spoken_lines(script)).replace(", ", ", … ")
        voice_path = work / "voice.wav"
        duration, engine, tts_words = speech.synthesize(
            spoken,
            voice_path,
            payload.get("voiceIdentifier") or settings.get("voiceIdentifier") or channel.get("defaultVoice"),
            float(payload.get("voiceSpeed") or settings.get("voiceSpeed") or 1.0),
        )
        self.project["ttsEngine"] = engine
        if engine == "silence":
            warnings = list(self.project.get("warnings") or [])
            warnings.append("No Kokoro at :8880 and no edge-tts CLI — export continues without a spoken VO. SAPI is not used.")
            self.project["warnings"] = warnings
        if tts_words:
            cues = captionlib.force_align_to_script(cues, tts_words)
            self.project["captions"] = cues
        if abs(duration - board["duration"]) > 0.8:
            board = boardlib.rescale(board, duration)
            if board["beats"][0]["role"] != "hook":
                raise boardlib.StoryboardError()
            self.project["storyboard"] = board

        self._emit("User files, stock, then ComfyUI if up", 0.48)
        assignments, ledger, warnings, cards_only = footage.gather(
            board["beats"],
            preset,
            self.project.get("aspect") or preset.get("aspect") or "9:16",
            work,
            settings.get("pexelsKey") or None,
            bool(settings.get("usePexels", True)),
            channel.get("name") or "",
            payload.get("localFiles") or [],
            pixabay_key=settings.get("pixabayKey") or None,
            use_pixabay=bool(settings.get("usePixabay", True)),
            use_local_models=bool(settings.get("useLocalModels", True)),
            models_dir=settings.get("modelsDir") or None,
            local_mode=payload.get("localMode") or settings.get("localMode") or "stock-first",
            comfy_url=settings.get("comfyUrl") or None,
            comfy_settings=settings,
            on_progress=lambda detail: self._emit(detail, 0.5),
        )
        self.project["warnings"] = list(self.project.get("warnings") or []) + warnings
        self.project["cardsOnly"] = cards_only
        allow_cards = bool(payload.get("allowCards") or settings.get("allowCards"))
        if cards_only and not allow_cards:
            raise ValueError(
                "This export would be cards, not a real video. Add a Pexels or Pixabay key, "
                "drop local footage, start ComfyUI at 127.0.0.1:8188, or check “cards ok” "
                "if you really want a type-card export."
            )

        self._emit("Sidechain duck −18 dB under speech, −8 dB in gaps", 0.62)
        music_path = work / "music.wav"
        music_source = self._resolve_music(channel, preset, music_path, duration)
        ledger.append({
            "id": "music",
            "kind": "audio",
            "source": music_source,
            "license": (
                "User imported" if music_source == "user-folder"
                else "Generated in-app" if music_source == "ace-step"
                else "Original-safe bundled bed"
            ),
            "credit": (
                "Imported music folder" if music_source == "user-folder"
                else "ACE-Step local" if music_source == "ace-step"
                else f"ReelForge {preset.get('music', {}).get('mood', 'pulse')} bed"
            ),
        })
        ledger.append({
            "id": "voice",
            "kind": "audio",
            "source": engine,
            "license": "Generated voiceover",
            "credit": engine,
        })
        self.project["licenseLedger"] = ledger

        self._emit("One-encode EDL → H.264 +faststart", 0.72)
        stem = publish.slugify(publish.make_title(self.project["topic"], script, self.project.get("seriesName")))
        folder = videos_dir() / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}-{stem[:40]}"
        result = renderer.compose(
            board,
            preset,
            self.project.get("aspect") or preset.get("aspect") or "9:16",
            assignments,
            cues if settings.get("burnCaptions", True) else [],
            voice_path,
            music_path,
            work,
            folder,
            stem,
            channel,
            script,
            bool(settings.get("burnCaptions", True)),
            bool(settings.get("exportSRT", True)),
            on_progress=lambda detail: self._emit(detail, 0.8),
            caption_style=caption_styles.style_by_id(self.project.get("captionStyleID")),
        )
        credits = [entry["credit"] for entry in ledger]
        pack = publish.write_pack(
            self.project["topic"],
            script,
            board,
            preset,
            channel,
            self.project.get("seriesName"),
            self.project.get("target") or "short",
            credits,
        )
        pack["thumbnailPaths"] = result["thumbs"]
        pack["thumbnailPath"] = result["thumb"]
        pack["srtPath"] = result["srt"]
        (folder / f"{stem}.json").write_text(json.dumps(pack, indent=2), encoding="utf-8")
        (folder / f"{stem}.credits.json").write_text(json.dumps(ledger, indent=2), encoding="utf-8")
        self.project["publishPack"] = pack
        self.project["exportPath"] = result["mp4"]
        self.pending = None
        self.progress = {"detail": f"Exported {Path(result['mp4']).name}", "fraction": 1, "busy": False, "finished": True}
        return self.snapshot()

    def _resolve_music(self, channel: dict[str, Any], preset: dict[str, Any], dest: Path, duration: float) -> str:
        folder = channel.get("musicFolderPath") or ""
        if folder and Path(folder).is_dir():
            audio = [p for p in Path(folder).iterdir() if p.suffix.lower() in {".wav", ".mp3", ".m4a", ".aiff"}]
            if audio:
                import shutil
                shutil.copy2(audio[0], dest)
                return "user-folder"
        if music.try_ace_step(dest, preset.get("music", {}).get("mood") or "pulse", int(preset.get("music", {}).get("bpm") or 120), duration):
            return "ace-step"
        music.write_loop(preset.get("music", {}).get("mood") or "pulse", int(preset.get("music", {}).get("bpm") or 120), dest, duration)
        return "bundled-bed"

    def _try_ollama(self, topic: str, preset: dict[str, Any], duration: int) -> tuple[dict[str, Any], str | None]:
        model = speech.probe_ollama()
        if not model:
            return scriptlib.write(topic, preset["id"], duration), None
        prompt = scriptlib.ollama_prompt(topic, preset, duration)
        try:
            with httpx.Client(timeout=45) as client:
                response = client.post(
                    "http://127.0.0.1:11434/api/generate",
                    json={"model": model, "prompt": prompt, "stream": False},
                )
                if response.status_code == 200:
                    raw = response.json().get("response") or ""
                    return scriptlib.parse_model_output(raw, topic, preset["id"]), None
        except Exception:
            pass
        return scriptlib.write(topic, preset["id"], duration), "Ollama missed — used the template writer."

    def _emit(self, detail: str, fraction: float) -> None:
        self.progress = {"detail": detail, "fraction": fraction, "busy": True}


DIRECTOR = Director()
