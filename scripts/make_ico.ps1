Add-Type -AssemblyName System.Drawing

$srcPath = "$PSScriptRoot\..\assets\icons\logo.jpg"
$dstPath = "$PSScriptRoot\..\assets\icons\velqi_tray.ico"

$img  = [System.Drawing.Image]::FromFile((Resolve-Path $srcPath).Path)
$bmp  = New-Object System.Drawing.Bitmap($img, 256, 256)
$ico  = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$fs   = [System.IO.File]::Open($dstPath, [System.IO.FileMode]::Create)
$ico.Save($fs)
$fs.Close()
$ico.Dispose()
$bmp.Dispose()
$img.Dispose()

Write-Host "ICO creado: $dstPath"
