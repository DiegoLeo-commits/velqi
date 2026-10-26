# PowerShell script to build optimized site-packages.zip and bundle into python_app.zip
$ErrorActionPreference = "Stop"

$rootPath = "C:\Users\Admin\Desktop\Nueva carpeta\Harmony-Music"
Set-Location $rootPath

Write-Host "== Creando site-packages.zip optimizado para Velqi (ZipImport) =="

$srcPkgs = "build/python-site-packages/x86_64"
$tempDir = "build/temp_site_packages"
$tempArchDir = "$tempDir/x86_64"

if (-not (Test-Path $srcPkgs)) {
    Write-Error "ERROR: No se encontraron los site-packages en $srcPkgs. Ejecute el paso 1 de serious_python primero."
    exit 1
}

# Limpiar temporales previos si existen
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}

# Crear carpetas temporales
New-Item -ItemType Directory -Force -Path $tempArchDir

# Copiar paquetes
Write-Host "Copiando paquetes desde $srcPkgs..."
Copy-Item -Path "$srcPkgs/*" -Destination $tempArchDir -Recurse -Force

# Ejecutar trim de extractores de yt-dlp para ahorrar espacio y agilizar carga
Write-Host "Recortando extractores innecesarios de yt-dlp..."
python scripts/trim_ytdlp.py $tempDir

# Compilar todos los scripts a bytecode binario .pyc para una importacion mas rapida
Write-Host "Precompilando scripts Python a bytecode (.pyc)..."
python -m compileall -b -f -q $tempArchDir

# Eliminar los archivos fuente de texto (.py) dejando solo los archivos binarios (.pyc)
Write-Host "Eliminando archivos fuente (.py) para reducir peso..."
Get-ChildItem -Path $tempArchDir -Filter "*.py" -Recurse | Remove-Item -Force

# Eliminar carpetas __pycache__ vacias que no son necesarias
Get-ChildItem -Path $tempArchDir -Filter "__pycache__" -Recurse | Remove-Item -Recurse -Force

# Comprimir en python/site-packages.zip
Write-Host "Comprimiendo site-packages a python/site-packages.zip..."
if (Test-Path "python/site-packages.zip") {
    Remove-Item -Path "python/site-packages.zip" -Force
}
Compress-Archive -Path "$tempArchDir/*" -DestinationPath "python/site-packages.zip" -Force

# Limpiar temporales
Remove-Item -Path $tempDir -Recurse -Force

# Generar el assets/python_app.zip final que serious_python leera
Write-Host "Empaquetando todo en assets/python_app.zip..."
if (Test-Path "assets/python_app.zip") {
    Remove-Item -Path "assets/python_app.zip" -Force
}
# Empaquetamos la app con el zip de dependencias dentro
Compress-Archive -Path python\main.py, python\ytdlp_backend.py, python\ytmusic_backend.py, python\cookies.txt, python\site-packages.zip -DestinationPath assets\python_app.zip -Force

Write-Host "== PROCESO DE ZIP COMPLETADO CON ÉXITO =="
