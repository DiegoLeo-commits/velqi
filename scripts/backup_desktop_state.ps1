# ============================================================
# backup_desktop_state.ps1
# Crea un backup completo del estado funcional de Velqi Desktop
# Ejecutar desde la raiz del proyecto:
#   powershell -ExecutionPolicy Bypass -File scripts/backup_desktop_state.ps1
# ============================================================
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = Get-Location }

$Release = Join-Path $Root "build\windows\x64\runner\Release"
$BackupDir = Join-Path $Root "backups\desktop_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

Write-Host "=== Velqi Desktop State Backup ===" -ForegroundColor Cyan
Write-Host "Project: $Root"
Write-Host "Release: $Release"
Write-Host "Backup:  $BackupDir"

# 1. Verify we have a working build
if (-not (Test-Path (Join-Path $Release "velqi.exe"))) {
    Write-Host "ERROR: velqi.exe not found in Release" -ForegroundColor Red
    exit 1
}

$hasAppSo = Test-Path (Join-Path $Release "data\app.so")
$hasAssets = Test-Path (Join-Path $Release "data\flutter_assets")
$hasPyZip = Test-Path (Join-Path $Release "data\flutter_assets\assets\python_app.zip")

Write-Host ""
Write-Host "Build verification:" -ForegroundColor Yellow
Write-Host "  velqi.exe:        OK"
Write-Host "  data/app.so:      $(if ($hasAppSo) {'OK'} else {'MISSING'})"
Write-Host "  flutter_assets:   $(if ($hasAssets) {'OK'} else {'MISSING'})"
Write-Host "  python_app.zip:   $(if ($hasPyZip) {'OK'} else {'MISSING'})"

# 2. Create backup directory
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

# 3. Copy Release directory (only essential files)
Write-Host ""
Write-Host "Copying Release files..." -ForegroundColor Yellow

$filesToCopy = @(
    "velqi.exe",
    "flutter_windows.dll",
    "icudtl.dat",
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "msvcp140.dll"
)

foreach ($f in $filesToCopy) {
    $src = Join-Path $Release $f
    if (Test-Path $src) {
        Copy-Item $src $BackupDir -Force
        Write-Host "  + $f" -ForegroundColor Green
    }
}

# Copy DLLs directory
$srcDlls = Join-Path $Release "DLLs"
if (Test-Path $srcDlls) {
    Copy-Item $srcDlls (Join-Path $BackupDir "DLLs") -Recurse -Force
    Write-Host "  + DLLs/" -ForegroundColor Green
}

# Copy data/ directory (app.so, flutter_assets)
$srcData = Join-Path $Release "data"
if (Test-Path $srcData) {
    Copy-Item $srcData (Join-Path $BackupDir "data") -Recurse -Force
    Write-Host "  + data/ (app.so, flutter_assets)" -ForegroundColor Green
}

# Copy all native plugin DLLs
Get-ChildItem $Release -Filter "*_plugin.dll" | ForEach-Object {
    Copy-Item $_.FullName $BackupDir -Force
    Write-Host "  + $($_.Name)" -ForegroundColor Green
}

# Copy python3 DLLs if present
Get-ChildItem $Release -Filter "python3*.dll" | ForEach-Object {
    Copy-Item $_.FullName $BackupDir -Force
    Write-Host "  + $($_.Name)" -ForegroundColor Green
}

# 4. Save source state snapshot
Write-Host ""
Write-Host "Saving source state snapshot..." -ForegroundColor Yellow

$snapshotDir = Join-Path $BackupDir "source_snapshot"
New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null

Copy-Item (Join-Path $Root "pubspec.yaml") $snapshotDir -Force
Copy-Item (Join-Path $Root "pubspec.lock") $snapshotDir -Force
Copy-Item (Join-Path $Root "lib\services\audio_handler.dart") $snapshotDir -Force
Copy-Item (Join-Path $Root "lib\ui\utils\theme_controller.dart") $snapshotDir -Force
Copy-Item (Join-Path $Root "python\main.py") $snapshotDir -Force
Copy-Item (Join-Path $Root "assets\python_app.zip") $snapshotDir -Force

# Save git info
Push-Location $Root
$commitHash = git rev-parse HEAD 2>$null
$branchName = git branch --show-current 2>$null
Pop-Location

@"
# Velqi Desktop Backup Info
Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Git Branch: $branchName
Git Commit: $commitHash

## Key Changes (what makes desktop work)
1. pubspec.yaml: just_audio_windows: ^0.2.3 (replaces just_audio_media_kit)
2. audio_handler.dart: Removed JustAudioMediaKit init for Windows
3. theme_controller.dart: DWM crash fix (try-catch around platform channel)
4. app_icon.ico: Updated logo

## Build Requirements
- Flutter Windows build: flutter build windows --release
- cmake install may fail (known issue) - copy files manually after build
- vcruntime140.dll MUST be 64-bit (PE32+) - check with: file vcruntime140.dll
- app.so goes in: Release/data/app.so
- flutter_assets goes in: Release/data/flutter_assets/

## Python Backend
- Requires: Python 3.11+ with yt-dlp and ytmusicapi installed
- Install: pip install yt-dlp ytmusicapi
- Backend auto-extracts python_app.zip on first launch
- Backend runs on localhost:8765
"@ | Set-Content (Join-Path $BackupDir "BACKUP_INFO.md")

Write-Host "  + source_snapshot/" -ForegroundColor Green
Write-Host "  + BACKUP_INFO.md" -ForegroundColor Green

# 5. Create zip
Write-Host ""
Write-Host "Creating portable zip..." -ForegroundColor Yellow
$zipPath = Join-Path $Root "backups\velqi_desktop_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
Compress-Archive -Path "$BackupDir\*" -DestinationPath $zipPath -Force
Write-Host "  $zipPath" -ForegroundColor Green

# 6. Summary
Write-Host ""
Write-Host "=== Backup Complete ===" -ForegroundColor Cyan
Write-Host "Folder: $BackupDir"
Write-Host "Zip:    $zipPath"
$size = (Get-ChildItem $BackupDir -Recurse | Measure-Object -Property Length -Sum).Sum
Write-Host "Size:   $([math]::Round($size / 1MB, 2)) MB"
