# 蓝牙音频模式切换器

一款面向 Windows 11 x64 的 Flutter 桌面应用，用于在蓝牙耳机的 **A2DP 高音质模式**与 **HFP 通话模式**之间快速切换。

应用支持系统托盘操作、HFP 话筒活动检测、登录自启和全局单实例，适用于 AirPods Max 以及其他同时提供 A2DP/HFP 音频端点的蓝牙耳机。

## 主要功能

- 根据 Windows `ContainerId` 关联同一耳机的 A2DP、HFP 输出和 HFP 输入端点，不依赖设备显示名称。
- 一键切换到 A2DP：使用高质量播放端点，并关闭所选耳机的 HFP 输入/输出端点。
- 一键切换到 HFP：恢复话筒端点，并配置对应的默认输入和输出。
- 检测目标耳机话筒是否存在活动音频会话，独立显示“HFP 活动中”。
- 深色 Material 3 设置界面和系统托盘快捷菜单。
- 保存目标耳机和期望模式，设备重连后自动恢复配置。
- 登录 Windows 后后台启动，关闭窗口时继续驻留托盘。
- 全局单实例；重复启动时唤醒已经运行的窗口。

## 模式说明

Windows 11 的新蓝牙音频驱动通常使用统一播放端点：启用 HFP 后，只有应用真正打开耳机话筒时，蓝牙传输才会进入 HFP。

因此界面会分别显示：

- **当前音频配置**：A2DP、HFP、混合状态或离线。
- **HFP 活动状态**：话筒当前是否正被录音、通话或语音应用占用。

切换到 HFP 后显示“HFP 未活动”是正常现象；打开录音或通话应用后，状态应在约 1 秒内变为“HFP 活动中”。

## 系统要求

### 运行环境

- Windows 11 x64
- 同时支持 A2DP 与 HFP 的蓝牙耳机
- 安装时需要管理员权限；日常使用不需要重复确认 UAC

### 开发环境

- Flutter 3.44 或更高版本
- Visual Studio 2022，并安装 **Desktop development with C++**
- Windows 11 SDK
- Inno Setup 6（仅构建安装程序时需要）

## 从源码构建

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

Release 输出目录：

```text
build\windows\x64\runner\Release
```

如果当前环境设置了 HTTP 代理且 `flutter test` 无法连接本地测试进程，可临时设置：

```powershell
$env:NO_PROXY = "127.0.0.1,localhost"
$env:no_proxy = $env:NO_PROXY
flutter test
```

## 安装与卸载

完成 Release 构建后，可以直接运行安装脚本：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

安装脚本会请求一次管理员权限，将应用复制到 `Program Files`、注册配套服务、创建开始菜单快捷方式并启动应用。

卸载：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

卸载流程会停止应用与服务，并尝试恢复由本软件管理的音频端点。

### 构建 Inno Setup 安装包

```powershell
.\scripts\build_installer.ps1 -Flutter (Get-Command flutter.bat).Source
```

输出文件：

```text
installer\output\BluetoothAudioManager-Setup.exe
```

### 构建便携分发包

```powershell
.\scripts\package_portable.ps1 -Version "1.0.0"
```

生成的 ZIP 位于 `build` 目录。ZIP 本身不是免安装版，解压后仍需运行其中的 `install.ps1` 注册服务。

## 使用方法

1. 打开应用并选择目标蓝牙耳机。
2. 选择“切换到 A2DP”获得高质量播放，或选择“切换到 HFP”启用耳机话筒。
3. 观察“HFP 活动中”状态，确认录音或通话应用是否正在占用话筒。
4. 关闭主窗口后，应用会继续驻留在任务栏通知区域。

托盘菜单包含：

- HFP 活动状态
- A2DP/HFP 动态切换项
- 退出

左键单击托盘图标可重新打开设置窗口。

## 诊断

建议将诊断结果写入文件，因为 Windows GUI 程序不一定将输出显示在当前终端：

```powershell
.\build\windows\x64\runner\Release\bluetooth_audio_manager.exe `
  --diagnostics-file .\diagnostics.txt
```

也可以通过命令行切换第一台已连接的兼容耳机：

```powershell
.\build\windows\x64\runner\Release\bluetooth_audio_manager.exe --switch-mode a2dp
.\build\windows\x64\runner\Release\bluetooth_audio_manager.exe --switch-mode hfp
```

诊断和命令行切换不受 GUI 单实例限制。

## 项目结构

```text
lib/                 Flutter UI、状态模型和平台通道
windows/runner/      Windows 音频端点、会话检测和桌面入口
windows/service/     配套 Windows 服务与端点恢复逻辑
scripts/             构建、安装、卸载和打包脚本
installer/           Inno Setup 配置
test/                Dart 单元测试
```

## 兼容性与限制

- 仅支持 Windows 11 x64，不构建 Android、iOS、macOS 或 Linux 版本。
- 一次只控制用户选中的一台蓝牙耳机。
- 切换模式会修改 Windows 默认播放和录音端点。
- 其他音频管理软件可能修改默认端点，应用会将这种不完整配置显示为“混合状态”。
- 默认音频端点和端点可见性切换依赖 Windows 的 `PolicyConfig` COM 接口；Windows 大版本更新后应重新进行实机验证。
- 某些通话软件会自行选择音频设备，不完全遵循 Windows 默认端点设置。

## 提交代码前检查

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build windows --release
```

