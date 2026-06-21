param(
  [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$release = Join-Path $projectRoot "build\windows\x64\runner\Release"
$packageRoot = Join-Path $projectRoot "build\package\BluetoothAudioManager"
$archive = Join-Path $projectRoot "build\BluetoothAudioManager-$Version-win-x64.zip"

if (-not (Test-Path (Join-Path $release "bluetooth_audio_manager.exe"))) {
  throw "Run 'flutter build windows --release' before packaging."
}

Remove-Item $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $packageRoot "app") | Out-Null
Copy-Item (Join-Path $release "*") (Join-Path $packageRoot "app") -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot "install.ps1") $packageRoot
Copy-Item (Join-Path $PSScriptRoot "uninstall.ps1") $packageRoot
Copy-Item (Join-Path $projectRoot "README.md") $packageRoot
Remove-Item $archive -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $archive -CompressionLevel Optimal
Write-Host $archive
