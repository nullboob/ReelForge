# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller onedir spec. Build on Windows with build-windows.ps1. Do not bundle torch."""

from pathlib import Path

from PyInstaller.utils.hooks import collect_submodules

spec_dir = Path(SPECPATH).resolve().parent
repo = spec_dir.parent
core_resources = repo / "Sources" / "ReelForgeCore" / "Resources"

datas = [
    (str(spec_dir / "reelforge" / "web"), "reelforge/web"),
    (str(spec_dir / "reelforge" / "models"), "reelforge/models"),
    (str(spec_dir / "reelforge" / "workflows"), "reelforge/workflows"),
    (str(core_resources / "presets"), "Sources/ReelForgeCore/Resources/presets"),
    (str(core_resources / "caption-styles"), "Sources/ReelForgeCore/Resources/caption-styles"),
    (str(core_resources / "fonts"), "Sources/ReelForgeCore/Resources/fonts"),
    (str(core_resources / "models"), "Sources/ReelForgeCore/Resources/models"),
]

hiddenimports = collect_submodules("reelforge") + [
    "uvicorn.logging",
    "uvicorn.loops",
    "uvicorn.loops.auto",
    "uvicorn.protocols",
    "uvicorn.protocols.http",
    "uvicorn.protocols.http.auto",
    "uvicorn.lifespan",
    "uvicorn.lifespan.on",
    "webview",
    "PIL",
    "httpx",
    "multipart",
]

a = Analysis(
    [str(spec_dir / "reelforge" / "__main__.py")],
    pathex=[str(spec_dir)],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["torch", "diffusers", "ltx_pipelines", "comfy", "moviepy", "remotion"],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="ReelForge",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    icon=str(repo / "scripts" / "ReelForge.icns") if (repo / "scripts" / "ReelForge.icns").exists() else None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    name="ReelForge",
)
