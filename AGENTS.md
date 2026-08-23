# BluetoothManager 开发指南

本文件面向维护者和 AI 编程代理。面向最终用户的说明位于 `README.md`，版本历史位于 `CHANGELOG.md`。

## 项目边界

- 目标平台仅为 Windows 11 x64；不要添加 Android、iOS、macOS 或 Linux 构建产物。
- Flutter 负责界面与状态编排，`windows/runner` 负责 Core Audio、`PolicyConfig` 和平台通道，`windows/service` 负责安装后的端口恢复服务。
- 使用 Windows `ContainerId` 关联同一蓝牙耳机的 A2DP、HFP 播放和 HFP 录音端口。
- 音频策略调用可能持续数秒，必须在原生后台线程执行；不要在 Flutter 窗口消息线程中执行轮询、休眠或耗时 COM 调用。
- 用户已有的工作树改动必须保留。修改前先运行 `git status --short`。

## 环境与依赖

- Flutter 3.44 或更高版本
- Visual Studio 2022，包含 **Desktop development with C++**
- Windows 11 SDK
- Inno Setup 6（仅构建安装程序时需要）

首次检出后运行：

```powershell
flutter pub get
```

## 调试

直接启动桌面应用：

```powershell
flutter run -d windows
```

将兼容设备和音频端口诊断写入文件：

```powershell
.\build\windows\x64\runner\Debug\bluetooth_audio_manager.exe `
  --diagnostics-file .\diagnostics.txt
```

从命令行切换第一台已连接的兼容耳机：

```powershell
.\build\windows\x64\runner\Debug\bluetooth_audio_manager.exe --switch-mode a2dp
.\build\windows\x64\runner\Debug\bluetooth_audio_manager.exe --switch-mode hfp
```

诊断与命令行切换不受 GUI 单实例限制。若状态异常，优先核对设备 `ContainerId`、默认播放/录音端口、HFP 录音端口可见性以及配套服务状态。

## 检查与测试

提交前至少运行：

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build windows --release
```

若代理设置导致测试无法连接本地进程：

```powershell
$env:NO_PROXY = "127.0.0.1,localhost"
$env:no_proxy = $env:NO_PROXY
flutter test
```

涉及 UI 的改动还需以 680×540 最小窗口检查深色与浅色主题，并更新 `docs/screenshots` 中的真实应用截图。

## 安装与卸载

完成 Release 构建后安装当前工作树版本：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

卸载并恢复本软件管理的音频端口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

安装与卸载会修改服务、应用目录、快捷方式和登录启动项，执行前应确认目标机器允许这些变更。

## 打包与发布

版本号需要同步更新：

- `pubspec.yaml`（版本号和 build number）
- `lib/windows_settings_page.dart`
- `windows/runner/Runner.rc` 的无构建系统回退值
- `installer/BluetoothAudioManager.iss`
- `scripts/package_portable.ps1`
- `README.md`、`CHANGELOG.md` 和相关测试

构建安装程序：

```powershell
.\scripts\build_installer.ps1 -Flutter (Get-Command flutter.bat).Source
```

构建完整 ZIP：

```powershell
.\scripts\package_portable.ps1 -Version "1.0.2"
```

发布前确认以下产物存在且版本正确：

```text
installer\output\BluetoothAudioManager-Setup-v1.0.2.exe
build\BluetoothAudioManager-1.0.2-win-x64.zip
```

最后检查差异、提交并推送 `main`，创建带有上述两个资产的 `v1.0.2` GitHub Release。Release 说明应与 `CHANGELOG.md` 对应。
