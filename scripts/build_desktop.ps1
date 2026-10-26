# ============================================================
# build_desktop.ps1
# Build completo de Velqi Desktop Windows
# Ejecutar desde la raiz del proyecto:
#   powershell -ExecutionPolicy Bypass -File scripts/build_desktop.ps1
# ============================================================
# "Continue" (not "Stop"): native tools (taskkill/flutter) write progress to
# stderr and PS 5.1 would abort on it. Real failures are caught by the
# explicit verification steps below.
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = Get-Location }

# Environment
$env:JAVA_HOME = "C:\Users\Usuario\jdk17\jdk-17.0.20+8"
$env:ANDROID_HOME = "C:\Android\Sdk"
$Release = Join-Path $Root "build\windows\x64\runner\Release"

Write-Host "=== Velqi Desktop Build ===" -ForegroundColor Cyan
Write-Host "Project: $Root"

# 1. Kill any running instance
Write-Host ""
Write-Host "1. Stopping running instances..." -ForegroundColor Yellow
cmd /c "taskkill /f /im velqi.exe >nul 2>&1"
Start-Sleep -Seconds 2

# 2. Note: extraction is pure Dart now (ytmusicapi_dart + ANDROID player
# endpoint) — no Python, no backend server, nothing to install.
Write-Host ""
Write-Host "2. Extraction engine: native Dart (no Python) - OK" -ForegroundColor Green

# 3. Verify pubspec uses media_kit/libmpv for desktop playback (replaces the
#    fragile just_audio_windows/WMF engine: it chokes on googlevideo URLs with
#    sourceNotSupported and second-song 00:00 hangs).
Write-Host ""
Write-Host "3. Verifying dependencies..." -ForegroundColor Yellow
$pubspec = Get-Content (Join-Path $Root "pubspec.yaml") -Raw
if ($pubspec -match "just_audio_media_kit") {
    Write-Host "   just_audio_media_kit (libmpv): OK" -ForegroundColor Green
} else {
    Write-Host "   just_audio_media_kit: MISSING - add to pubspec.yaml" -ForegroundColor Red
    exit 1
}
if ($pubspec -match "just_audio_windows") {
    Write-Host "   WARNING: just_audio_windows still present - it is not used anymore." -ForegroundColor Yellow
}

# 4. Run flutter pub get
Write-Host ""
Write-Host "4. Running flutter pub get..." -ForegroundColor Yellow
flutter pub get 2>&1 | Select-Object -Last 3

# 5. Run dart analyze
Write-Host ""
Write-Host "5. Running dart analyze..." -ForegroundColor Yellow
$analysis = dart analyze lib/services/audio_handler.dart lib/ui/utils/theme_controller.dart 2>&1
$errors = $analysis | Select-String -Pattern "error" -SimpleMatch
if ($errors) {
    Write-Host "   ERRORS FOUND:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "   No errors" -ForegroundColor Green
}

# 6. Build Windows
Write-Host ""
Write-Host "6. Building Windows release..." -ForegroundColor Yellow
$buildStart = Get-Date
flutter build windows --release 2>&1 | Select-Object -Last 5
$buildDuration = ((Get-Date) - $buildStart).TotalSeconds
Write-Host "   Build completed in $([math]::Round($buildDuration))s"

# 7. Verify build output
Write-Host ""
Write-Host "7. Verifying build output..." -ForegroundColor Yellow
if (-not (Test-Path (Join-Path $Release "velqi.exe"))) {
    Write-Host "   ERROR: velqi.exe not found!" -ForegroundColor Red
    exit 1
}
Write-Host "   velqi.exe: OK" -ForegroundColor Green

# 8. Copy flutter_assets to data/
Write-Host ""
Write-Host "8. Copying assets to Release..." -ForegroundColor Yellow
$flutterAssetsSrc = Join-Path $Root "build\flutter_assets"
$dataDir = Join-Path $Release "data"

if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }

# Remove old flutter_assets in data/ and copy fresh
if (Test-Path (Join-Path $dataDir "flutter_assets")) {
    Remove-Item (Join-Path $dataDir "flutter_assets") -Recurse -Force
}
if (Test-Path $flutterAssetsSrc) {
    Copy-Item $flutterAssetsSrc (Join-Path $dataDir "flutter_assets") -Recurse -Force
    Write-Host "   flutter_assets -> data/ OK" -ForegroundColor Green
}

# Copy app.so to data/
$appSoSrc = Join-Path $Root "build\windows\app.so"
if (Test-Path $appSoSrc) {
    Copy-Item $appSoSrc (Join-Path $dataDir "app.so") -Force
    Write-Host "   app.so -> data/ OK" -ForegroundColor Green
}

# Remove stale root-level copies
Remove-Item (Join-Path $Release "app.so") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Release "flutter_assets") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Release "icudtl.dat") -Force -ErrorAction SilentlyContinue

# 9. Fix vcruntime DLLs (must be 64-bit)
Write-Host ""
Write-Host "9. Checking vcruntime DLLs..." -ForegroundColor Yellow
$vr140 = Get-Item (Join-Path $Release "vcruntime140.dll") -ErrorAction SilentlyContinue
if ($vr140) {
    $bytes = [System.IO.File]::ReadAllBytes($vr140.FullName)
    $is64 = ($bytes[0x18] -eq 0x20B)  # PE32+
    if (-not $is64) {
        Write-Host "   vcruntime140.dll is 32-bit! Fixing..." -ForegroundColor Red
        $vcRedist = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT"
        if (Test-Path "$vcRedist\vcruntime140.dll") {
            Copy-Item "$vcRedist\vcruntime140.dll" (Join-Path $Release "vcruntime140.dll") -Force
            Copy-Item "$vcRedist\msvcp140.dll" (Join-Path $Release "msvcp140.dll") -Force
            Write-Host "   Fixed: 64-bit DLLs installed" -ForegroundColor Green
        }
    } else {
        Write-Host "   vcruntime140.dll: 64-bit OK" -ForegroundColor Green
    }
}

# 10. Copy plugin DLLs from build directory
Write-Host ""
Write-Host "10. Ensuring all plugin DLLs are present..." -ForegroundColor Yellow
$buildDir = Join-Path $Root "build\windows\x64\runner\Release"
$pluginDlls = Get-ChildItem $buildDir -Filter "*_plugin.dll" -ErrorAction SilentlyContinue
foreach ($dll in $pluginDlls) {
    $target = Join-Path $Release $dll.Name
    if (-not (Test-Path $target) -or $dll.LastWriteTime -gt (Get-Item $target -ErrorAction SilentlyContinue).LastWriteTime) {
        Copy-Item $dll.FullName $target -Force
        Write-Host "   + $($dll.Name)" -ForegroundColor Green
    }
}

# smtc_windows is an FFI plugin with a PREBUILT Rust DLL that cmake install
# (broken on this machine) never copies. Without it the app logs
# "Failed to load dynamic library 'smtc_windows.dll'" and media keys die.
$smtcSrc = Join-Path $Root "windows\flutter\ephemeral\.plugin_symlinks\smtc_windows\windows\smtc_windows-v0.1.3\windows-x64\smtc_windows.dll"
if ((Test-Path $smtcSrc) -and -not (Test-Path (Join-Path $Release "smtc_windows.dll"))) {
    Copy-Item $smtcSrc (Join-Path $Release "smtc_windows.dll") -Force
    Write-Host "   + smtc_windows.dll (prebuilt)" -ForegroundColor Green
}

# 11. Summary
Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Cyan
Write-Host "Release: $Release"
Write-Host "To run: cd build\windows\x64\runner\Release && .\velqi.exe"

$totalSize = (Get-ChildItem $Release -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host "Size:    $([math]::Round($totalSize / 1MB, 1)) MB"
