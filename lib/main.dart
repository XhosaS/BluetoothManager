import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_controller.dart';
import 'models.dart';
import 'window_size.dart';
import 'windows_settings_page.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);

  final options = WindowOptions(
    size: initialWindowSize(arguments),
    minimumSize: const Size(680, 540),
    center: true,
    title: '蓝牙音频模式切换器',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (arguments.contains('--background')) {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  });
  runApp(const BluetoothAudioManagerApp());
}

class BluetoothAudioManagerApp extends StatefulWidget {
  const BluetoothAudioManagerApp({super.key});

  @override
  State<BluetoothAudioManagerApp> createState() =>
      _BluetoothAudioManagerAppState();
}

class _BluetoothAudioManagerAppState extends State<BluetoothAudioManagerApp>
    with TrayListener, WindowListener {
  late final AppController controller;
  bool? _nativeDarkModeEnabled;

  @override
  void initState() {
    super.initState();
    controller = AppController()..addListener(_onChanged);
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initialize();
  }

  Future<void> _initialize() async {
    await trayManager.destroy();
    await trayManager.setIcon('assets/bluetooth_mode_tray.ico');
    await trayManager.setToolTip('蓝牙音频模式切换器');
    await controller.initialize();
    await _syncNativeDarkMode();
    await _updateTrayMenu();
  }

  void _onChanged() {
    _updateTrayMenu();
    if (!controller.loading) unawaited(_syncNativeDarkMode());
    if (mounted) setState(() {});
  }

  Future<void> _syncNativeDarkMode() async {
    final enabled = controller.darkThemeEnabled;
    if (_nativeDarkModeEnabled == enabled) return;
    _nativeDarkModeEnabled = enabled;
    await controller.platform.setNativeDarkMode(enabled);
  }

  Future<void> _updateTrayMenu() async {
    final device = controller.selectedDevice;
    final disabled = controller.applyingMode || device == null;
    await trayManager.setContextMenu(
      Menu(
        items: <MenuItem>[
          MenuItem(
            key: 'hfp_activity',
            label: 'HFP 活动：${controller.status.hfpActive ? '是' : '否'}',
            disabled: true,
          ),
          MenuItem.checkbox(
            key: 'mode_a2dp',
            label: '切换到 A2DP',
            checked: isTrayModeSelected(controller.desiredMode, 'mode_a2dp'),
            disabled: disabled,
          ),
          MenuItem.checkbox(
            key: 'mode_hfp',
            label: '切换到 HFP',
            checked: isTrayModeSelected(controller.desiredMode, 'mode_hfp'),
            disabled: disabled,
          ),
          MenuItem.checkbox(
            key: 'mode_automatic',
            label: '自动',
            checked: isTrayModeSelected(
              controller.desiredMode,
              'mode_automatic',
            ),
            disabled: disabled,
          ),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
  }

  Future<void> _showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() {
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final mode = trayModeFromMenuKey(menuItem.key);
    if (mode != null) {
      controller.setMode(mode);
      return;
    }
    if (menuItem.key == 'exit') windowManager.destroy();
  }

  @override
  Future<void> onWindowClose() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    controller.dispose();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '蓝牙音频模式切换器',
      theme: _windowsTheme(Brightness.light),
      darkTheme: _windowsTheme(Brightness.dark),
      themeMode: controller.darkThemeEnabled ? ThemeMode.dark : ThemeMode.light,
      home: WindowsSettingsPage(controller: controller),
    );
  }
}

ThemeData _windowsTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Microsoft YaHei UI',
    fontFamilyFallback: const <String>['Microsoft YaHei', 'Segoe UI', 'Arial'],
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF666666),
      brightness: brightness,
      surface: dark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
    ),
    scaffoldBackgroundColor: dark
        ? const Color(0xFF202020)
        : const Color(0xFFF3F3F3),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: dark ? const Color(0xFF333333) : const Color(0xFFEAEAEA),
    focusColor: dark ? const Color(0xFF3A3A3A) : const Color(0xFFE1E1E1),
    dividerColor: dark ? const Color(0xFF303030) : const Color(0xFFE1E1E1),
  );
}
