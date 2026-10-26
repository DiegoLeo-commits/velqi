# ============================================================
# build_android_full.ps1
# Build completo de APK Android (split-per-abi)
# Ejecutar desde la raiz del proyecto:
#   powershell -ExecutionPolicy Bypass -File scripts/build_android_full.ps1
# ============================================================
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = Get-Location }

# Environment
$env:JAVA_HOME = "C:\Users\Usuario\jdk17\jdk-17.0.20+8"
$env:ANDROID_HOME = "C:\Android\Sdk"

Write-Host "=== Velqi Android Build ===" -ForegroundColor Cyan
Write-Host "Project: $Root"

# 1. Stop running instances
Write-Host ""
Write-Host "1. Cleaning up..." -ForegroundColor Yellow
taskkill //f //im velqi.exe 2>$null
taskkill //f //im python.exe 2>$null
Start-Sleep -Seconds 1

# 2. Verify dependencies
Write-Host ""
Write-Host "2. Verifying dependencies..." -ForegroundColor Yellow
if (-not $env:JAVA_HOME -or -not (Test-Path $env:JAVA_HOME)) {
    Write-Host "   ERROR: JAVA_HOME not set or invalid" -ForegroundColor Red
    exit 1
}
Write-Host "   JAVA_HOME: $env:JAVA_HOME" -ForegroundColor Green

flutter pub get 2>&1 | Select-Object -Last 3

# 3. Dart analyze
Write-Host ""
Write-Host "3. Running dart analyze..." -ForegroundColor Yellow
$errors = dart analyze lib/ 2>&1 | Select-String -Pattern "error " -SimpleMatch
if ($errors) {
    Write-Host "   ERRORS:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
    $continue = Read-Host "   Continue anyway? (y/N)"
    if ($continue -ne "y") { exit 1 }
} else {
    Write-Host "   No errors" -ForegroundColor Green
}

# 4. Build APK
Write-Host ""
Write-Host "4. Building APK (split-per-abi)..." -ForegroundColor Yellow
$buildStart = Get-Date

flutter build apk --release --split-per-abi --android-skip-build-dependency-validation 2>&1 | Select-Object -Last 10

$buildDuration = ((Get-Date) - $buildStart).TotalSeconds
Write-Host "   Build completed in $([math]::Round($buildDuration))s"

# 5. Find APKs
Write-Host ""
Write-Host "5. Locating APKs..." -ForegroundColor Yellow
$apkDir = Join-Path $Root "build\app\outputs\flutter-apk"
$apks = Get-ChildItem $apkDir -Filter "app-*-release.apk" -ErrorAction SilentlyContinue

if ($apks) {
    foreach ($apk in $apks) {
        $sizeMB = [math]::Round($apk.Length / 1MB, 1)
        Write-Host "   $($apk.Name) - $sizeMB MB" -ForegroundColor Green
    }
} else {
    Write-Host "   WARNING: No APKs found in $apkDir" -ForegroundColor Red
}

# 6. Summary
Write-Host ""
Write-Host "=== Android Build Complete ===" -ForegroundColor Cyan
Write-Host "APKs: $apkDir"

# Copy to releases directory
$releasesDir = Join-Path $Root "releases"
New-Item -ItemType Directory -Path $releasesDir -Force | Out-Null
if ($apks) {
    foreach ($apk in $apks) {
        Copy-Item $apk.FullName $releasesDir -Force
        Write-Host "Copied: $($apk.Name)" -ForegroundColor Green
    }
}
