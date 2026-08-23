param(
  [string]$Flutter = "D:\Flutter\flutter\bin\flutter.bat",
  [string]$Iscc = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$isccCandidates = @(
  $Iscc
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$Iscc = $isccCandidates | Select-Object -First 1
if (-not $Iscc) {
  throw "Inno Setup 6 was not found. Install JRSoftware.InnoSetup or pass -Iscc."
}
Push-Location $projectRoot
try {
  & $Flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "Flutter release build failed." }
  & $Iscc "installer\BluetoothAudioManager.iss"
  if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed." }
} finally {
  Pop-Location
}
