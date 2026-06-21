param(
  [string]$Destination = (Join-Path $env:ProgramFiles "Bluetooth Audio Manager")
)

$ErrorActionPreference = "Stop"
$serviceName = "BluetoothAudioManagerService"
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Destination `"$Destination`""
  $elevatedProcess = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
  exit $elevatedProcess.ExitCode
}

& taskkill.exe /F /IM bluetooth_audio_manager.exe 2>$null | Out-Null
& sc.exe stop $serviceName 2>$null | Out-Null
Start-Sleep -Milliseconds 750
$serviceExe = Join-Path $Destination "bluetooth_audio_service.exe"
if (Test-Path $serviceExe) { & $serviceExe --restore }
& sc.exe delete $serviceName 2>$null | Out-Null

Remove-Item (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Bluetooth Audio Manager.lnk") -Force -ErrorAction SilentlyContinue
Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "BluetoothAudioManager" -Force -ErrorAction SilentlyContinue
Remove-Item $Destination -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Bluetooth Audio Manager was removed."
