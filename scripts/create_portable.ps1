# ============================================================
# create_portable.ps1
# Crea el zip portable de Velqi Desktop para distribucion
# Ejecutar desde la raiz del proyecto:
#   powershell -ExecutionPolicy Bypass -File scripts/create_portable.ps1
# ============================================================
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = Get-Location }

$Release = Join-Path $Root "build\windows\x64\runner\Release"
$OutputDir = Join-Path $Root "releases"

Write-Host "=== Velqi Desktop Portable Packager ===" -ForegroundColor Cyan

# 1. Verify build exists
if (-not (Test-Path (Join-Path $Release "velqi.exe"))) {
    Write-Host "ERROR: No build found. Run build_desktop.ps1 first." -ForegroundColor Red
    exit 1
}

# 2. Create output dir
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# 3. Get version from settings_screen_controller.dart
$versionFile = Get-Content (Join-Path $Root "lib\ui\screens\Settings\settings_screen_controller.dart") -Raw
$versionMatch = [regex]::Match($versionFile, "currentVersion\s*=\s*'([^']+)'")
$version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "1.3.1" }
Write-Host "Version: $version" -ForegroundColor Green

# 4. Create staging directory
$staging = Join-Path $Root "build\portable_staging"
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging -Force | Out-Null

# 5. Copy essential files
Write-Host ""
Write-Host "Staging files..." -ForegroundColor Yellow

# Main exe and engine
Copy-Item (Join-Path $Release "velqi.exe") $staging
Copy-Item (Join-Path $Release "flutter_windows.dll") $staging
Copy-Item (Join-Path $Release "icudtl.dat") $staging -ErrorAction SilentlyContinue

# VC Runtime
Copy-Item (Join-Path $Release "vcruntime140.dll") $staging -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Release "vcruntime140_1.dll") $staging -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Release "msvcp140.dll") $staging -ErrorAction SilentlyContinue

# Plugin DLLs
Get-ChildItem $Release -Filter "*_plugin.dll" | ForEach-Object { Copy-Item $_.FullName $staging }
Get-ChildItem $Release -Filter "python3*.dll" | ForEach-Object { Copy-Item $_.FullName $staging }
Copy-Item (Join-Path $Release "audiotags.dll") $staging -ErrorAction SilentlyContinue

# DLLs directory (Python stdlib + dependencies)
if (Test-Path (Join-Path $Release "DLLs")) {
    Copy-Item (Join-Path $Release "DLLs") (Join-Path $staging "DLLs") -Recurse -Force
}

# Lib directory (Python stdlib)
if (Test-Path (Join-Path $Release "Lib")) {
    Copy-Item (Join-Path $Release "Lib") (Join-Path $staging "Lib") -Recurse -Force
}

# Data directory (app.so + flutter_assets)
if (Test-Path (Join-Path $Release "data")) {
    Copy-Item (Join-Path $Release "data") (Join-Path $staging "data") -Recurse -Force
}

# 6. Create README for the portable
@"
Velqi v$version - Desktop (Windows)
====================================
Requirements:
  - Python 3.11+ installed and in PATH
  - Install dependencies: pip install yt-dlp ytmusicapi

To run:
  1. Double-click velqi.exe
  2. The app will extract its backend automatically on first launch
  3. Enjoy your music!

If playback fails:
  - Make sure Python is installed and accessible from command line
  - Make sure yt-dlp is up to date: pip install -U yt-dlp
  - Check that no firewall is blocking localhost:8765

Version: $version
Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@ | Set-Content (Join-Path $staging "README.txt")

# 7. Create zip
$zipName = "velqi-desktop-v${version}.zip"
$zipPath = Join-Path $OutputDir $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Write-Host ""
Write-Host "Creating zip: $zipName" -ForegroundColor Yellow
Compress-Archive -Path "$staging\*" -DestinationPath $zipPath -CompressionLevel Optimal

# 8. Cleanup staging
Remove-Item $staging -Recurse -Force

# 9. Summary
$zipSize = (Get-Item $zipPath).Length
Write-Host ""
Write-Host "=== Portable Package Ready ===" -ForegroundColor Cyan
Write-Host "File: $zipPath"
Write-Host "Size: $([math]::Round($zipSize / 1MB, 1)) MB"
