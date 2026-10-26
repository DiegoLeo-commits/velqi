$env:SERIOUS_PYTHON_SITE_PACKAGES = "C:\Users\Admin\Desktop\Nueva carpeta\Harmony-Music\build\python-site-packages"
Write-Host "SERIOUS_PYTHON_SITE_PACKAGES = $env:SERIOUS_PYTHON_SITE_PACKAGES"
Write-Host "== PASO 2: flutter build apk --release --split-per-abi =="
flutter build apk --release --split-per-abi
Write-Host "== FIN =="
