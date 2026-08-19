# Build ReelForge.exe + Inno installer on a Windows box.
# Linux CI cannot produce a real .exe. Do not run this in GitHub Actions.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
  Write-Error "Python launcher 'py' is missing. Install Python 3.12+ from python.org (user install, no admin needed)."
}

if (-not (Test-Path ".venv")) {
  py -3.12 -m venv .venv
}
. .\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt pyinstaller
if (-not $?) { python -m pip install -r requirements.txt pyinstaller }

# Optional: drop a pre-fetched LGPL ffmpeg.exe into vendor\ffmpeg\ so the onedir has a binary.
# The first-run wizard can also download ffmpeg into %LOCALAPPDATA%\ReelForge\bin.

python -m PyInstaller --noconfirm --clean ReelForge.spec
if (-not (Test-Path "dist\ReelForge\ReelForge.exe")) {
  Write-Error "PyInstaller did not write dist\ReelForge\ReelForge.exe"
}

$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($iscc) {
  & $iscc "installer\ReelForge.iss"
} else {
  Write-Host "Inno Setup not installed. The onedir app is in dist\ReelForge\. Install Inno to wrap an installer."
}

Write-Host "Smoke: launch dist\ReelForge\ReelForge.exe, finish the wizard with Instant, draft + Accept a 15s short."
