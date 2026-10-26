# Post-build Windows: copies Python packages + generates installer + portable zip
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot + "\.."
$releaseDir = "$root\build\windows\x64\runner\Release"

Set-Location $root

Write-Host "== Verificando build de Windows =="
if (-not (Test-Path "$releaseDir\velqi.exe")) {
    Write-Error "velqi.exe no encontrado en $releaseDir. Ejecuta flutter build windows --release primero."
    exit 1
}

Write-Host "== Copiando paquetes Python al directorio de Release =="
$sitePackagesSrc = "$root\build\python-site-packages\x86_64"
$sitePackagesDst = "$releaseDir\Lib\site-packages"

if (-not (Test-Path $sitePackagesSrc)) {
    Write-Error "No se encontraron site-packages en $sitePackagesSrc. Ejecuta el build de Android primero (crea los paquetes)."
    exit 1
}

New-Item -ItemType Directory -Force -Path $sitePackagesDst | Out-Null
Copy-Item -Path "$sitePackagesSrc\*" -Destination $sitePackagesDst -Recurse -Force
Write-Host "  OK: paquetes Python copiados a $sitePackagesDst"

# Verify total size
$totalMB = [math]::Round((Get-ChildItem $releaseDir -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Host "  Tamano total de Release: ${totalMB}MB"

Write-Host ""
Write-Host "== Generando instalador con Inno Setup =="
$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (Test-Path $iscc) {
    & $iscc "$root\windows\packaging\exe\inno_setup.iss"
    if ($LASTEXITCODE -eq 0) {
        $installerPath = "$root\windows\packaging\exe\Velqi-1.3.1-Setup.exe"
        if (Test-Path $installerPath) {
            $installerMB = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
            Write-Host "  OK: Instalador generado -> $installerPath (${installerMB}MB)"
        } else {
            Write-Warning "Inno Setup termino pero no se encontro el instalador."
        }
    } else {
        Write-Warning "Inno Setup fallo. Continuando con el zip portable..."
    }
} else {
    Write-Warning "Inno Setup no encontrado. Solo se generara el zip portable."
}

Write-Host ""
Write-Host "== Generando ZIP portable =="
$portableZip = "$root\Velqi-1.3.1-Windows-Portable.zip"
if (Test-Path $portableZip) { Remove-Item $portableZip -Force }
Compress-Archive -Path "$releaseDir\*" -DestinationPath $portableZip -Force
$zipMB = [math]::Round((Get-Item $portableZip).Length / 1MB, 1)
Write-Host "  OK: ZIP portable -> $portableZip (${zipMB}MB)"

Write-Host ""
Write-Host "== LISTO =="
Write-Host "  Instalador: windows\packaging\exe\Velqi-1.3.1-Setup.exe"
Write-Host "  Portable:   Velqi-1.3.1-Windows-Portable.zip"
