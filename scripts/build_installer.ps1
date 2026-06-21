param(
  [string]$Flutter = "D:\Flutter\flutter\bin\flutter.bat",
  [string]$Iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
  & $Flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "Flutter release build failed." }
  if (-not (Test-Path $Iscc)) {
    throw "Inno Setup 6 was not found at: $Iscc"
  }
  & $Iscc "installer\BluetoothAudioManager.iss"
  if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed." }
} finally {
  Pop-Location
}
