import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_controller.dart';
import 'models.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);

  const options = WindowOptions(
    size: Size(760, 620),
    minimumSize: Size(680, 540),
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

  @override
  void initState() {
    super.initState();
    controller = AppController()..addListener(_onChanged);
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initialize();
  }

  Future<void> _initialize() async {
    // Clear any stale Shell notification icon left by an older build before
    // registering the current icon resource.
    await trayManager.destroy();
    await trayManager.setIcon('assets/bluetooth_mode_tray.ico');
    await trayManager.setToolTip('蓝牙音频模式切换器');
    await controller.initialize();
    await _updateTrayMenu();
  }

  void _onChanged() {
    _updateTrayMenu();
    if (mounted) setState(() {});
  }

  Future<void> _updateTrayMenu() async {
    final device = controller.selectedDevice;
    final target = trayToggleTarget(
      controller.status.mode,
      controller.desiredMode,
    );
    await trayManager.setContextMenu(
      Menu(
        items: <MenuItem>[
          MenuItem(
            key: 'hfp_activity',
            label: 'HFP 活动：${controller.status.hfpActive ? '是' : '否'}',
            disabled: true,
          ),
          MenuItem(
            key: 'toggle_mode',
            label: target == BluetoothAudioMode.a2dp ? '切换到 A2DP' : '切换到 HFP',
            disabled: controller.applyingMode || device == null,
          ),
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
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle_mode':
        controller.setMode(
          trayToggleTarget(controller.status.mode, controller.desiredMode),
        );
        break;
      case 'exit':
        windowManager.destroy();
        break;
    }
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
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7898FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF111827),
        ),
        useMaterial3: true,
        // Use one Windows-native family for both Chinese and Latin glyphs so
        // mixed labels such as “切换到 A2DP” keep a consistent stroke weight.
        fontFamily: 'Microsoft YaHei UI',
        fontFamilyFallback: const <String>[
          'Microsoft YaHei',
          'Segoe UI',
          'Arial',
        ],
        scaffoldBackgroundColor: const Color(0xFF080C16),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF080C16),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF111827),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF232D42)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0C1322),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2A3650)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF7898FF), width: 1.5),
          ),
        ),
      ),
      home: ModernSettingsPage(controller: controller),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.controller, super.key});
  final AppController controller;

  Color _modeColor(BluetoothAudioMode mode) => switch (mode) {
    BluetoothAudioMode.a2dp => const Color(0xFF15803D),
    BluetoothAudioMode.hfp => const Color(0xFF2563EB),
    BluetoothAudioMode.mixed => const Color(0xFFD97706),
    BluetoothAudioMode.offline => const Color(0xFF64748B),
  };

  @override
  Widget build(BuildContext context) {
    final device = controller.selectedDevice;
    final status = controller.status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('蓝牙音频模式切换器'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _DeviceCard(controller: controller),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _modeColor(status.mode),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                status.mode.label,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Text('期望：${controller.desiredMode.label}'),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: <Widget>[
                              _StatusChip(
                                label: '耳机连接',
                                active: status.connected,
                              ),
                              _StatusChip(
                                label: '话筒可用',
                                active: status.microphoneEnabled,
                              ),
                              _StatusChip(
                                label: 'HFP 活动中',
                                active: status.hfpActive,
                              ),
                              _StatusChip(
                                label: 'A2DP 默认',
                                active: status.a2dpIsDefault,
                              ),
                              _StatusChip(
                                label: 'HFP 输出就绪',
                                active:
                                    status.hfpRenderIsDefault ||
                                    (status.mode == BluetoothAudioMode.hfp &&
                                        status.a2dpIsDefault),
                              ),
                              _StatusChip(
                                label: 'HFP 输入默认',
                                active: status.hfpCaptureIsDefault,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed:
                                      device == null || controller.applyingMode
                                      ? null
                                      : () => controller.setMode(
                                          BluetoothAudioMode.a2dp,
                                        ),
                                  icon: const Icon(Icons.high_quality),
                                  label: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    child: Text('切换到 A2DP'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed:
                                      device == null || controller.applyingMode
                                      ? null
                                      : () => controller.setMode(
                                          BluetoothAudioMode.hfp,
                                        ),
                                  icon: const Icon(Icons.mic),
                                  label: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 14),
                                    child: Text('切换到 HFP'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (controller.applyingMode) ...<Widget>[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: SwitchListTile(
                      title: const Text('登录 Windows 后自动启动'),
                      subtitle: const Text('后台启动并仅显示任务栏通知区域图标'),
                      value: controller.launchAtStartupEnabled,
                      onChanged: controller.setLaunchAtStartup,
                    ),
                  ),
                  if (controller.error != null) ...<Widget>[
                    const SizedBox(height: 16),
                    _ErrorBanner(message: controller.error!),
                  ],
                ],
              ),
            ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '目标蓝牙耳机',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: controller.selectedDevice?.id,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '请选择同时支持 A2DP 和 HFP 的耳机',
              ),
              items: controller.devices
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(
                        '${item.name}${item.connected ? '' : '（离线）'}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: controller.selectDevice,
            ),
            if (controller.devices.isEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const Text('未找到兼容设备。请确认耳机已配对并至少连接过一次。'),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        active ? Icons.check_circle : Icons.cancel,
        size: 18,
        color: active ? const Color(0xFF15803D) : const Color(0xFF94A3B8),
      ),
      label: Text(label),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEE2E2),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class ModernSettingsPage extends StatelessWidget {
  const ModernSettingsPage({required this.controller, super.key});
  final AppController controller;

  Color _modeColor(BluetoothAudioMode mode) => switch (mode) {
    BluetoothAudioMode.a2dp => const Color(0xFF55D6BE),
    BluetoothAudioMode.hfp => const Color(0xFF7898FF),
    BluetoothAudioMode.mixed => const Color(0xFFFFC56B),
    BluetoothAudioMode.offline => const Color(0xFF8290AA),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        titleSpacing: 24,
        title: const Row(
          children: <Widget>[
            _ModernAppIcon(),
            SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '蓝牙音频模式切换器',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  '在高音质与通话模式之间快速切换',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8D9AB3)),
                ),
              ],
            ),
          ],
        ),
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _ModernDeviceCard(controller: controller),
                      const SizedBox(height: 16),
                      _ModernModeCard(
                        controller: controller,
                        modeColor: _modeColor(controller.status.mode),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          secondary: const _ModernSettingIcon(),
                          title: const Text(
                            '登录 Windows 后自动启动',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text('后台启动，仅驻留在任务栏通知区域'),
                          value: controller.launchAtStartupEnabled,
                          onChanged: controller.setLaunchAtStartup,
                        ),
                      ),
                      if (controller.error != null) ...<Widget>[
                        const SizedBox(height: 16),
                        _ModernErrorBanner(message: controller.error!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _ModernDeviceCard extends StatelessWidget {
  const _ModernDeviceCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.headphones_rounded, color: Color(0xFF7898FF)),
                SizedBox(width: 10),
                Text(
                  '目标蓝牙耳机',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: controller.selectedDevice?.id,
              dropdownColor: const Color(0xFF151D2E),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.bluetooth_audio_rounded),
                hintText: '请选择同时支持 A2DP 和 HFP 的耳机',
              ),
              items: controller.devices
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(
                        '${item.name}${item.connected ? '' : '（离线）'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: controller.selectDevice,
            ),
            if (controller.devices.isEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const Text(
                '未找到兼容设备。请确认耳机已配对并至少连接过一次。',
                style: TextStyle(color: Color(0xFF8D9AB3)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModernModeCard extends StatelessWidget {
  const _ModernModeCard({required this.controller, required this.modeColor});
  final AppController controller;
  final Color modeColor;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final device = controller.selectedDevice;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A3650)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF17213A), Color(0xFF101725)],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: modeColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: modeColor.withValues(alpha: 0.4)),
                  ),
                  child: Icon(
                    status.mode == BluetoothAudioMode.a2dp
                        ? Icons.graphic_eq_rounded
                        : Icons.headset_mic_rounded,
                    color: modeColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        '当前音频配置',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8D9AB3),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status.mode.label,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _ModernActivityIndicator(active: status.hfpActive),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _ModernStatusPill(label: '耳机连接', active: status.connected),
                _ModernStatusPill(
                  label: '话筒可用',
                  active: status.microphoneEnabled,
                ),
                _ModernStatusPill(
                  label: 'A2DP 默认',
                  active: status.a2dpIsDefault,
                ),
                _ModernStatusPill(
                  label: 'HFP 输出就绪',
                  active:
                      status.hfpRenderIsDefault ||
                      (status.mode == BluetoothAudioMode.hfp &&
                          status.a2dpIsDefault),
                ),
                _ModernStatusPill(
                  label: 'HFP 输入默认',
                  active: status.hfpCaptureIsDefault,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: const Color(0xFF7898FF),
                      foregroundColor: const Color(0xFF071027),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: device == null || controller.applyingMode
                        ? null
                        : () => controller.setMode(BluetoothAudioMode.a2dp),
                    icon: const Icon(Icons.high_quality_rounded),
                    label: const Text('切换到 A2DP'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: device == null || controller.applyingMode
                        ? null
                        : () => controller.setMode(BluetoothAudioMode.hfp),
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('切换到 HFP'),
                  ),
                ),
              ],
            ),
            if (controller.applyingMode) ...<Widget>[
              const SizedBox(height: 16),
              const LinearProgressIndicator(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModernStatusPill extends StatelessWidget {
  const _ModernStatusPill({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF55D6BE) : const Color(0xFF71809B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            active ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _ModernActivityIndicator extends StatelessWidget {
  const _ModernActivityIndicator({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF55D6BE) : const Color(0xFF8290AA);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.mic_rounded, size: 16, color: color),
          const SizedBox(width: 7),
          Text(
            active ? 'HFP 活动中' : 'HFP 未活动',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModernAppIcon extends StatelessWidget {
  const _ModernAppIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: <Color>[Color(0xFF7898FF), Color(0xFF8B6CFF)],
      ),
      borderRadius: BorderRadius.circular(13),
      boxShadow: const <BoxShadow>[
        BoxShadow(color: Color(0x557898FF), blurRadius: 18),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Image.asset(
        'assets/app_icon.png',
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}

class _ModernSettingIcon extends StatelessWidget {
  const _ModernSettingIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: const Color(0xFF7898FF).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(
      Icons.power_settings_new_rounded,
      color: Color(0xFF9DB2FF),
    ),
  );
}

class _ModernErrorBanner extends StatelessWidget {
  const _ModernErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3A171D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF79343B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: Color(0xFFFFB4AB)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
