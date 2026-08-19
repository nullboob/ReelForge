const state = {
  presets: [],
  selected: "viral-hook",
  snapshot: null,
  target: "short",
  styles: [],
  captionStyleID: "tiktok-classic-outline",
  stockReady: false,
};

const $ = (id) => document.getElementById(id);

async function api(path, options) {
  const res = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || data.message || res.statusText);
  return data;
}

function chip(label, on) {
  const el = document.createElement("span");
  el.className = "chip" + (on ? " on" : "");
  el.textContent = label;
  return el;
}

function renderStatus(status) {
  const box = $("chips");
  box.innerHTML = "";
  box.append(
    chip(status.ttsEngine || "edge-tts", true),
    chip(status.anyReady ? "Models Ready" : "Core (no weights)", !!status.anyReady),
    chip(status.pexels ? "Pexels" : "No Pexels", !!status.pexels),
    chip(status.pixabay ? "Pixabay" : "No Pixabay", !!status.pixabay),
    chip(status.ollama ? "Ollama" : "LLM off", !!status.ollama),
    chip(status.ffmpeg ? "ffmpeg" : "No ffmpeg", !!status.ffmpeg),
    chip(status.kokoro ? "Kokoro" : "Kokoro off", !!status.kokoro),
    chip(status.comfy?.up ? "Comfy" : "Comfy off", !!status.comfy?.up),
    chip(status.comfy?.ltx ? "LTX" : "LTX off", !!status.comfy?.ltx),
    chip(status.comfy?.wan ? "Wan" : "Wan off", !!status.comfy?.wan),
    chip(status.comfy?.qwen ? "Qwen" : "Qwen off", !!status.comfy?.qwen),
  );
  renderComfyChips(status.comfy);
  renderModelSlots(status.models);
  $("engine").textContent = `Engine: ${status.ttsEngine || "edge-tts"}`;
  state.styles = status.captionStyles || state.styles;
  state.stockReady = !!status.stockReady;
  renderStyles();
  $("cards-warn").hidden = state.stockReady || !!status.anyReady || !!status.comfy?.up;
  const voice = $("voice");
  voice.innerHTML = `<option value="">Auto (Kokoro → Windows)</option>`;
  for (const item of status.voices || []) {
    const opt = document.createElement("option");
    opt.value = item.id;
    opt.textContent = item.name;
    voice.appendChild(opt);
  }
}

function renderPresets() {
  const q = $("search").value.toLowerCase();
  const box = $("presets");
  box.innerHTML = "";
  for (const preset of state.presets) {
    const hay = `${preset.name} ${preset.tagline} ${preset.id}`.toLowerCase();
    if (q && !hay.includes(q)) continue;
    const card = document.createElement("button");
    card.type = "button";
    card.className = "preset" + (preset.id === state.selected ? " on" : "");
    const a = preset.coverGradient?.[0] || "#FF4D6D";
    const b = preset.coverGradient?.[1] || "#2B0A12";
    card.innerHTML = `<div class="swatch" style="background:linear-gradient(135deg,${a},${b})"></div>
      <div class="preset-meta"><strong>${preset.name}</strong><span>${preset.aspect} · ${preset.durationSec}s · ${preset.tagline}</span></div>`;
    card.onclick = () => {
      state.selected = preset.id;
      state.captionStyleID = defaultStyleForPreset(preset.id);
      renderPresets();
      renderStyles();
    };
    box.appendChild(card);
  }
}

function defaultStyleForPreset(presetID) {
  const map = {
    "viral-hook": "tiktok-classic-outline",
    "faceless-facts": "hormozi-yellow-pop",
    "youtube-short-news": "commentary-telegraph",
    motivational: "bounce-fitness",
    "podcast-clip": "podcast-split-karaoke",
    "travel-vlog": "quiet-aesthetic-min",
  };
  return map[presetID] || "tiktok-classic-outline";
}

function styleSwatch(style) {
  const stops = (style.gradient && style.gradient.length ? style.gradient : [style.fill || "#fff", style.highlight || style.plateFill || "#111"]).join(",");
  return `linear-gradient(135deg, ${stops})`;
}

function renderComfyChips(comfy) {
  const box = $("comfy-chips");
  if (!box) return;
  box.innerHTML = "";
  box.append(
    chip(comfy?.up ? "Comfy" : "Comfy off", !!comfy?.up),
    chip(comfy?.ltx ? "LTX" : "LTX off", !!comfy?.ltx),
    chip(comfy?.wan ? "Wan" : "Wan off", !!comfy?.wan),
    chip(comfy?.qwen ? "Qwen" : "Qwen off", !!comfy?.qwen),
  );
}

function renderModelSlots(catalog) {
  const box = $("model-slots");
  if (!box) return;
  box.innerHTML = "";
  for (const slot of catalog?.slots || []) {
    const row = document.createElement("div");
    row.className = "model-slot" + (slot.ready ? " on" : "");
    row.innerHTML = `<span>${slot.name}</span><span>${slot.ready ? "Ready" : "Missing"}</span>`;
    box.appendChild(row);
  }
}

function renderStyles() {
  const box = $("style-grid");
  if (!box) return;
  box.innerHTML = "";
  for (const style of state.styles) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "style-chip" + (style.id === state.captionStyleID ? " on" : "");
    btn.innerHTML = `<div class="swatch" style="background:${styleSwatch(style)}"></div><span>${style.name}</span>`;
    btn.onclick = () => {
      state.captionStyleID = style.id;
      $("style-name").textContent = style.name;
      renderStyles();
    };
    box.appendChild(btn);
  }
  const current = state.styles.find((s) => s.id === state.captionStyleID);
  if (current) $("style-name").textContent = current.name;
}

function fillDesk(project) {
  $("desk-hook").value = project.script?.hook || "";
  $("desk-cta").value = project.script?.cta || "";
  const body = $("desk-body");
  body.innerHTML = "";
  for (const line of project.script?.body || []) {
    const input = document.createElement("input");
    input.value = line;
    body.appendChild(input);
  }
  const caps = $("desk-captions");
  caps.innerHTML = "";
  for (const cue of project.captions || []) {
    const input = document.createElement("input");
    input.value = cue.text;
    caps.appendChild(input);
  }
  const beats = project.storyboard?.beats || [];
  $("desk-meta").textContent = beats.slice(0, 6).map((b) => `${b.role}: ${Math.round(b.duration * 10) / 10}s`).join("  ·  ");
}

function applySnapshot(snap) {
  state.snapshot = snap;
  const project = snap.project || {};
  const awaiting = !!snap.awaitingAccept;
  $("desk").hidden = !awaiting;
  $("btn-accept").hidden = !awaiting;
  if (awaiting) fillDesk(project);
  $("progress-detail").textContent = snap.progress?.detail || "";
  $("bar").style.width = `${Math.round((snap.progress?.fraction || 0) * 100)}%`;
  $("error").hidden = !snap.progress?.failed;
  if (snap.progress?.failed) $("error").textContent = snap.progress.detail;
  const pack = project.publishPack;
  $("pack").hidden = !pack;
  if (pack) {
    $("pack-title").textContent = pack.title;
    $("pack-desc").textContent = pack.description;
    $("pack-reminder").textContent = pack.syntheticReminder;
    $("pack-tags").textContent = (pack.tags || []).join(" · ");
    $("pack-chapters").textContent = (pack.chapters || []).slice(0, 6).map((c) => `${c.timestamp} ${c.title}`).join("  ·  ");
  }
  const exported = !!project.exportPath;
  $("btn-reveal").disabled = !exported;
  $("player").hidden = !exported;
  $("empty").hidden = exported;
  if (exported) {
    $("player").src = `/api/media?t=${Date.now()}`;
  }
  $("btn-draft").disabled = !!snap.progress?.busy || awaiting;
  $("btn-draft").textContent = snap.progress?.busy ? "Working…" : (awaiting ? "Draft ready" : "Draft script");
}

function draftPayload() {
  return {
    topic: $("topic").value,
    presetID: state.selected,
    target: state.target,
    seriesName: $("series").value,
    useLocalAI: $("use-local").checked,
    useLocalModels: $("use-local-models").checked,
    localMode: $("local-mode").value || "stock-first",
    usePexels: $("use-pexels").checked,
    usePixabay: $("use-pixabay").checked,
    useUnsplash: $("use-unsplash").checked,
    voiceIdentifier: $("voice").value || null,
    captionStyleID: state.captionStyleID,
    allowCards: $("allow-cards").checked,
  };
}

function deskPayload() {
  return {
    hook: $("desk-hook").value,
    body: [...$("desk-body").querySelectorAll("input")].map((el) => el.value),
    cta: $("desk-cta").value,
    captions: [...$("desk-captions").querySelectorAll("input")].map((el) => el.value),
    captionStyleID: state.captionStyleID,
    allowCards: $("allow-cards").checked,
    localMode: $("local-mode").value || "stock-first",
  };
}

async function draft() {
  $("error").hidden = true;
  try {
    applySnapshot(await api("/api/draft", { method: "POST", body: JSON.stringify(draftPayload()) }));
  } catch (err) {
    $("error").hidden = false;
    $("error").textContent = err.message;
  }
}

async function accept() {
  $("error").hidden = true;
  try {
    $("btn-accept").disabled = true;
    $("desk-accept").disabled = true;
    applySnapshot(await api("/api/accept", { method: "POST", body: JSON.stringify(deskPayload()) }));
  } catch (err) {
    $("error").hidden = false;
    $("error").textContent = err.message;
  } finally {
    $("btn-accept").disabled = false;
    $("desk-accept").disabled = false;
  }
}

async function boot() {
  const data = await api("/api/bootstrap");
  state.presets = data.presets;
  renderStatus(data.status);
  renderPresets();
  applySnapshot(data);
  const settings = data.settings || {};
  $("use-pexels").checked = settings.usePexels !== false;
  $("use-pixabay").checked = settings.usePixabay !== false;
  $("use-unsplash").checked = !!settings.useUnsplash;
  $("use-local").checked = settings.useLocalAI !== false;
  $("use-local-models").checked = settings.useLocalModels !== false;
  $("local-mode").value = settings.localMode || "stock-first";
  $("settings-local-mode").value = settings.localMode || "stock-first";
  $("allow-cards").checked = !!settings.allowCards;
  state.captionStyleID = settings.captionStyleID || defaultStyleForPreset(state.selected);
  $("pexels-key").value = settings.pexelsKey || "";
  $("pixabay-key").value = settings.pixabayKey || "";
  $("channel-name").value = settings.channel?.name || "";
  $("primary").value = settings.channel?.primaryHex || "#FF4D6D";
  $("accent").value = settings.channel?.accentHex || "#E8C39A";
  $("outro").checked = settings.channel?.outroEnabled !== false;
  $("music-folder").value = settings.channel?.musicFolderPath || "";
  $("models-dir").value = settings.modelsDir || "";
  $("comfy-url").value = settings.comfyUrl || "http://127.0.0.1:8188";
  $("ltx-ckpt").value = settings.ltxCkpt || "ltx-2.3-22b-distilled.safetensors";
  $("ltx-lora").value = settings.ltxLora || "ltx-2.3-22b-distilled-lora-384.safetensors";
  $("wan-ckpt").value = settings.wanCkpt || "wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors";
  $("wan-lora").value = settings.wanLora || "lightx2v_T2V_14B_cfg_step_distill_v2.safetensors";
  $("qwen-ckpt").value = settings.qwenCkpt || "qwen_image_fp8_e4m3fn.safetensors";
  $("qwen-lora").value = settings.qwenLora || "Qwen-Image-Lightning-8steps-V1.0.safetensors";
}

$("search").oninput = renderPresets;
$("btn-draft").onclick = draft;
$("btn-accept").onclick = accept;
$("desk-accept").onclick = accept;
$("add-beat").onclick = () => {
  const input = document.createElement("input");
  $("desk-body").appendChild(input);
};
$("btn-new").onclick = async () => applySnapshot(await api("/api/new", { method: "POST", body: "{}" }));
$("btn-reveal").onclick = () => api("/api/reveal", { method: "POST", body: "{}" });
$("btn-settings").onclick = () => { $("settings").hidden = false; };
$("settings-close").onclick = () => { $("settings").hidden = true; };
$("save-settings").onclick = async () => {
  await api("/api/settings", {
    method: "POST",
    body: JSON.stringify({
      pexelsKey: $("pexels-key").value,
      pixabayKey: $("pixabay-key").value,
      usePexels: $("use-pexels").checked,
      usePixabay: $("use-pixabay").checked,
      captionStyleID: state.captionStyleID,
      allowCards: $("allow-cards").checked,
      useUnsplash: $("use-unsplash").checked,
      useLocalAI: $("use-local").checked,
      useLocalModels: $("use-local-models").checked,
      localMode: $("settings-local-mode").value || $("local-mode").value || "stock-first",
      comfyUrl: $("comfy-url").value || "http://127.0.0.1:8188",
      ltxCkpt: $("ltx-ckpt").value,
      ltxLora: $("ltx-lora").value,
      wanCkpt: $("wan-ckpt").value,
      wanLora: $("wan-lora").value,
      qwenCkpt: $("qwen-ckpt").value,
      qwenLora: $("qwen-lora").value,
      modelsDir: $("models-dir").value,
      burnCaptions: $("burn").checked,
      exportSRT: $("srt").checked,
      voiceIdentifier: $("voice").value || null,
      channel: {
        name: $("channel-name").value,
        primaryHex: $("primary").value,
        accentHex: $("accent").value,
        outroEnabled: $("outro").checked,
        musicFolderPath: $("music-folder").value,
      },
    }),
  });
  $("settings").hidden = true;
};
$("local-mode").onchange = () => {
  $("settings-local-mode").value = $("local-mode").value;
};
$("settings-local-mode").onchange = () => {
  $("local-mode").value = $("settings-local-mode").value;
};
$("scan-comfy").onclick = async () => {
  await api("/api/settings", {
    method: "POST",
    body: JSON.stringify({ comfyUrl: $("comfy-url").value || "http://127.0.0.1:8188" }),
  });
  renderComfyChips(await api("/api/comfy"));
};
$("scan-models").onclick = async () => {
  const catalog = await api("/api/models", {
    method: "POST",
    body: JSON.stringify({ modelsDir: $("models-dir").value }),
  });
  renderModelSlots(catalog);
};
$("copy-title").onclick = () => navigator.clipboard.writeText($("pack-title").textContent);
$("copy-desc").onclick = () => navigator.clipboard.writeText($("pack-desc").textContent);
$("target").onclick = (event) => {
  const btn = event.target.closest("button");
  if (!btn) return;
  state.target = btn.dataset.value;
  for (const child of $("target").children) child.classList.toggle("on", child === btn);
};
document.addEventListener("keydown", (event) => {
  if (event.ctrlKey && event.key.toLowerCase() === "r") {
    event.preventDefault();
    draft();
  }
  if (event.ctrlKey && event.key === "Enter") {
    event.preventDefault();
    accept();
  }
});

boot().catch((err) => {
  $("error").hidden = false;
  $("error").textContent = err.message;
});
