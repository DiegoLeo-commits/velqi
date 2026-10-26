$env:SERIOUS_PYTHON_SITE_PACKAGES = "C:\Users\Admin\Desktop\Nueva carpeta\Harmony-Music\build\python-site-packages"

Write-Host "== PASO 1: Empaquetar site-packages Python para Android =="
dart run serious_python:main package python `
  --platform Android `
  --asset assets/python_app.zip `
  -r "yt-dlp==2026.07.04,ytmusicapi==1.12.1" `
  --cleanup

if ($LASTEXITCODE -ne 0) {
    Write-Error "Paso 1 fallo. Abortando."
    exit 1
}

Write-Host ""
Write-Host "== PASO 2: Compilar APKs por ABI =="
flutter build apk --release --split-per-abi

Write-Host ""
Write-Host "== Listo! APKs generados en build\app\outputs\flutter-apk\ =="
