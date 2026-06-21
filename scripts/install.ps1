param(
  [string]$Source = "",
  [string]$Destination = (Join-Path $env:ProgramFiles "Bluetooth Audio Manager")
)

$ErrorActionPreference = "Stop"
$packageSource = Join-Path $PSScriptRoot "app"
if ([string]::IsNullOrWhiteSpace($Source)) {
  $Source = if (Test-Path $packageSource) {
    $packageSource
  } else {
    Join-Path (Split-Path -Parent $PSScriptRoot) "build\windows\x64\runner\Release"
  }
}
$serviceName = "BluetoothAudioManagerService"
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Source `"$Source`" -Destination `"$Destination`""
  $elevatedProcess = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
  exit $elevatedProcess.ExitCode
}

if (-not (Test-Path (Join-Path $Source "bluetooth_audio_manager.exe"))) {
  throw "Release build not found at: $Source"
}

Get-Process bluetooth_audio_manager -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

$existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($null -ne $existingService) {
  if ($existingService.Status -ne "Stopped") {
    Stop-Service -Name $serviceName -Force -ErrorAction Stop
    $existingService.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(10))
  }
  & sc.exe delete $serviceName | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to remove the existing Windows service (sc.exe exit code $LASTEXITCODE)."
  }
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    if ($null -eq (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 250
  }
  if ($null -ne (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
    throw "The previous Windows service is still marked for deletion. Restart Windows and run the installer again."
  }
}
New-Item -ItemType Directory -Force $Destination | Out-Null
Copy-Item (Join-Path $Source "*") $Destination -Recurse -Force

$serviceExe = Join-Path $Destination "bluetooth_audio_service.exe"
if (-not (Test-Path $serviceExe)) {
  throw "Windows service executable not found after copying: $serviceExe"
}
$binaryPath = '"{0}"' -f $serviceExe
New-Service `
  -Name $serviceName `
  -BinaryPathName $binaryPath `
  -DisplayName "Bluetooth Audio Manager Service" `
  -Description "Controls Bluetooth headset microphone endpoints for the active user." `
  -StartupType Automatic `
  -ErrorAction Stop | Out-Null
& sc.exe description $serviceName "Controls Bluetooth headset microphone endpoints for the active user." | Out-Null
Start-Service -Name $serviceName -ErrorAction Stop
$installedService = Get-Service -Name $serviceName -ErrorAction Stop
$installedService.WaitForStatus("Running", [TimeSpan]::FromSeconds(10))

$appExe = Join-Path $Destination "bluetooth_audio_manager.exe"
$shell = New-Object -ComObject WScript.Shell
$startMenuDirectory = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
New-Item -ItemType Directory -Force $startMenuDirectory | Out-Null
$startMenu = Join-Path $startMenuDirectory "Bluetooth Audio Manager.lnk"
$installedIcon = Join-Path $Destination "data\flutter_assets\assets\bluetooth_mode_tray.ico"
if (-not (Test-Path $installedIcon)) {
  throw "Application icon not found after copying: $installedIcon"
}
Remove-Item -LiteralPath $startMenu -Force -ErrorAction SilentlyContinue
$shortcut = $shell.CreateShortcut($startMenu)
$shortcut.TargetPath = $appExe
$shortcut.WorkingDirectory = $Destination
$shortcut.IconLocation = "$installedIcon,0"
$shortcut.Save()

# Ask Explorer to discard stale shortcut and executable icon thumbnails.
$iconRefresh = Join-Path $env:SystemRoot "System32\ie4uinit.exe"
if (Test-Path $iconRefresh) {
  Start-Process -FilePath $iconRefresh -ArgumentList "-show" -Wait -WindowStyle Hidden
}

# Route through the existing desktop shell so the app starts unelevated.
Start-Process explorer.exe -ArgumentList ('"{0}"' -f $appExe)
Write-Host "Installed to $Destination"
