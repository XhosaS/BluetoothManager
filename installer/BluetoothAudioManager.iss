#define MyAppName "蓝牙音频模式切换器"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Xhosa"
#define MyAppExeName "bluetooth_audio_manager.exe"
#define ServiceName "BluetoothAudioManagerService"

[Setup]
AppId={{75F841B7-C16E-4691-9C8C-C46AF5B92F61}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Bluetooth Audio Manager
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=BluetoothAudioManager-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Run]
Filename: "{sys}\sc.exe"; Parameters: "create {#ServiceName} binPath= ""{app}\bluetooth_audio_service.exe"" start= auto DisplayName= ""Bluetooth Audio Manager Service"""; Flags: runhidden waituntilterminated
Filename: "{sys}\sc.exe"; Parameters: "description {#ServiceName} ""Controls Bluetooth headset microphone endpoints for the interactive user."""; Flags: runhidden waituntilterminated
Filename: "{sys}\sc.exe"; Parameters: "start {#ServiceName}"; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#MyAppExeName}"; Flags: runhidden waituntilterminated; RunOnceId: "StopApplication"
Filename: "{sys}\sc.exe"; Parameters: "stop {#ServiceName}"; Flags: runhidden waituntilterminated; RunOnceId: "StopService"
Filename: "{app}\bluetooth_audio_service.exe"; Parameters: "--restore"; Flags: runhidden waituntilterminated; RunOnceId: "RestoreEndpoints"
Filename: "{sys}\sc.exe"; Parameters: "delete {#ServiceName}"; Flags: runhidden waituntilterminated; RunOnceId: "DeleteService"
