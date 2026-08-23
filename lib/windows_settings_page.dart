import 'dart:async';

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';

enum _AppSection { audio, settings, about }

class WindowsSettingsPage extends StatefulWidget {
  const WindowsSettingsPage({required this.controller, super.key});

  final AppController controller;

  @override
  State<WindowsSettingsPage> createState() => _WindowsSettingsPageState();
}

class _WindowsSettingsPageState extends State<WindowsSettingsPage> {
  _AppSection section = _AppSection.audio;
  String? toastMessage;
  Timer? toastTimer;

  AppController get controller => widget.controller;

  @override
  void dispose() {
    toastTimer?.cancel();
    super.dispose();
  }

  void showToast(String message) {
    toastTimer?.cancel();
    setState(() => toastMessage = message);
    toastTimer = Timer(const Duration(milliseconds: 2100), () {
      if (mounted) setState(() => toastMessage = null);
    });
  }

  Future<void> setMode(BluetoothAudioMode mode) async {
    if (controller.applyingMode || controller.selectedDevice == null) return;
    await controller.setMode(mode);
    if (!mounted) return;
    showToast(controller.error == null ? '已切换到${mode.label}' : '模式切换未完成');
  }

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return Scaffold(
      body: Stack(
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final sidebarWidth = constraints.maxWidth < 800 ? 176.0 : 216.0;
              return Row(
                children: <Widget>[
                  SizedBox(
                    width: sidebarWidth,
                    child: _Sidebar(
                      section: section,
                      onChanged: (value) => setState(() => section = value),
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: palette.stroke,
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      child: KeyedSubtree(
                        key: ValueKey<_AppSection>(section),
                        child: switch (section) {
                          _AppSection.audio => _AudioPage(
                            controller: controller,
                            onModeChanged: setMode,
                            showToast: showToast,
                          ),
                          _AppSection.settings => _GeneralPage(
                            controller: controller,
                            showToast: showToast,
                          ),
                          _AppSection.about => const _AboutPage(),
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: IgnorePointer(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                offset: toastMessage == null
                    ? const Offset(0, 0.35)
                    : Offset.zero,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 130),
                  opacity: toastMessage == null ? 0 : 1,
                  child: _Toast(message: toastMessage ?? ''),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WinPalette {
  const _WinPalette({
    required this.canvas,
    required this.sidebar,
    required this.surface,
    required this.surfaceHover,
    required this.selection,
    required this.control,
    required this.stroke,
    required this.strokeStrong,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.indicator,
    required this.blue,
    required this.success,
    required this.switchOnTrack,
    required this.switchOnThumb,
  });

  final Color canvas;
  final Color sidebar;
  final Color surface;
  final Color surfaceHover;
  final Color selection;
  final Color control;
  final Color stroke;
  final Color strokeStrong;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color indicator;
  final Color blue;
  final Color success;
  final Color switchOnTrack;
  final Color switchOnThumb;

  static _WinPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const _WinPalette(
        canvas: Color(0xFF202020),
        sidebar: Color(0xFF1C1C1C),
        surface: Color(0xFF2B2B2B),
        surfaceHover: Color(0xFF333333),
        selection: Color(0xFF3A3A3A),
        control: Color(0xFF303030),
        stroke: Color(0xFF3B3B3B),
        strokeStrong: Color(0xFF565656),
        text: Color(0xFFF4F4F4),
        textSecondary: Color(0xFFC9C9C9),
        textTertiary: Color(0xFF9A9A9A),
        indicator: Color(0xFFD0D0D0),
        blue: Color(0xFF4AA3FF),
        success: Color(0xFF67C887),
        switchOnTrack: Color(0xFF5B5B5B),
        switchOnThumb: Color(0xFF080808),
      );
    }
    return const _WinPalette(
      canvas: Color(0xFFF3F3F3),
      sidebar: Color(0xFFEEEEEE),
      surface: Color(0xFFFBFBFB),
      surfaceHover: Color(0xFFF5F5F5),
      selection: Color(0xFFE2E2E2),
      control: Color(0xFFF8F8F8),
      stroke: Color(0xFFE2E2E2),
      strokeStrong: Color(0xFFC7C7C7),
      text: Color(0xFF1C1C1C),
      textSecondary: Color(0xFF5F5F5F),
      textTertiary: Color(0xFF7B7B7B),
      indicator: Color(0xFF555555),
      blue: Color(0xFF0067C0),
      success: Color(0xFF237A3B),
      switchOnTrack: Color(0xFF5D5D5D),
      switchOnThumb: Color(0xFFFFFFFF),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.section, required this.onChanged});

  final _AppSection section;
  final ValueChanged<_AppSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return ColoredBox(
      color: palette.sidebar,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
          child: Column(
            children: <Widget>[
              _NavItem(
                icon: Icons.headphones_outlined,
                label: '蓝牙音频',
                selected: section == _AppSection.audio,
                onTap: () => onChanged(_AppSection.audio),
              ),
              const SizedBox(height: 4),
              _NavItem(
                icon: Icons.tune_outlined,
                label: '常规设置',
                selected: section == _AppSection.settings,
                onTap: () => onChanged(_AppSection.settings),
              ),
              const Spacer(),
              _NavItem(
                icon: Icons.info_outline_rounded,
                label: '关于',
                selected: section == _AppSection.about,
                onTap: () => onChanged(_AppSection.about),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 46),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '版本 1.0.1',
                    style: TextStyle(fontSize: 11, color: palette.textTertiary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    final background = widget.selected
        ? palette.selection
        : hovered
        ? palette.surfaceHover
        : Colors.transparent;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            height: 44,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: hovered && !widget.selected
                    ? palette.strokeStrong
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 4,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: widget.selected ? 16 : 0,
                    decoration: BoxDecoration(
                      color: palette.indicator,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(widget.icon, size: 20, color: palette.textSecondary),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14,
                      fontWeight: widget.selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return ColoredBox(
      color: palette.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth < 620 ? 20.0 : 34.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(horizontal, 30, horizontal, 42),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: palette.text,
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          subtitle,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 25, bottom: 10, left: 2),
      child: Text(
        label,
        style: TextStyle(
          color: palette.text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AudioPage extends StatelessWidget {
  const _AudioPage({
    required this.controller,
    required this.onModeChanged,
    required this.showToast,
  });

  final AppController controller;
  final ValueChanged<BluetoothAudioMode> onModeChanged;
  final ValueChanged<String> showToast;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const _PageFrame(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return _PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _PageHeading(title: '蓝牙音频', subtitle: '选择耳机并设置音频切换策略'),
          const _SectionTitle('目标设备'),
          _DeviceSurface(controller: controller, showToast: showToast),
          const _SectionTitle('音频策略'),
          _ModeOption(
            icon: Icons.graphic_eq_rounded,
            title: 'A2DP 高音质',
            description: '使用高质量立体声播放，并关闭所选耳机的 HFP 输入与输出端点。',
            selected: controller.desiredMode == BluetoothAudioMode.a2dp,
            enabled:
                controller.selectedDevice != null && !controller.applyingMode,
            onTap: () => onModeChanged(BluetoothAudioMode.a2dp),
          ),
          const SizedBox(height: 6),
          _ModeOption(
            icon: Icons.mic_none_rounded,
            title: 'HFP 通话',
            description: '启用耳机话筒，并配置对应的默认输入与输出。',
            selected: controller.desiredMode == BluetoothAudioMode.hfp,
            enabled:
                controller.selectedDevice != null && !controller.applyingMode,
            onTap: () => onModeChanged(BluetoothAudioMode.hfp),
          ),
          const SizedBox(height: 6),
          _ModeOption(
            icon: Icons.sync_rounded,
            title: '自动模式',
            description: '话筒活动时进入 HFP，停止使用后恢复 A2DP 高音质。',
            selected: controller.desiredMode == BluetoothAudioMode.automatic,
            enabled:
                controller.selectedDevice != null && !controller.applyingMode,
            onTap: () => onModeChanged(BluetoothAudioMode.automatic),
          ),
          const _SectionTitle('当前状态'),
          _StatusStrip(controller: controller),
          if (controller.error != null) ...<Widget>[
            const SizedBox(height: 14),
            _ErrorBanner(message: controller.error!),
          ],
        ],
      ),
    );
  }
}

class _DeviceSurface extends StatelessWidget {
  const _DeviceSurface({required this.controller, required this.showToast});

  final AppController controller;
  final ValueChanged<String> showToast;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    final device = controller.selectedDevice;
    final connected = device?.connected ?? false;
    final description = controller.devices.isEmpty
        ? '未找到兼容设备，请确认耳机已配对并连接'
        : connected
        ? controller.applyingMode
              ? '正在应用音频策略…'
              : '已连接 · 支持 A2DP 与 HFP'
        : '设备离线 · 重新连接后自动恢复策略';

    Widget identity() => Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const _OutlineIcon(icon: Icons.headphones_outlined),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '蓝牙耳机',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: connected ? palette.blue : palette.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final picker = _DevicePicker(
      devices: controller.devices,
      value: device?.id,
      onChanged: (id) async {
        await controller.selectDevice(id);
        final selected = controller.selectedDevice;
        if (selected != null) showToast('已选择 ${selected.name}');
      },
    );

    return _HoverSurface(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                identity(),
                const SizedBox(height: 14),
                picker,
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: identity()),
              const SizedBox(width: 20),
              SizedBox(width: 260, child: picker),
            ],
          );
        },
      ),
    );
  }
}

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({
    required this.devices,
    required this.value,
    required this.onChanged,
  });

  final List<BluetoothAudioDevice> devices;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    final validValue = devices.any((device) => device.id == value)
        ? value
        : null;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: palette.strokeStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: validValue,
          hint: Text(
            devices.isEmpty ? '未找到兼容耳机' : '选择蓝牙耳机',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
          isExpanded: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: palette.textSecondary,
          ),
          borderRadius: BorderRadius.circular(6),
          dropdownColor: palette.surface,
          focusColor: Colors.transparent,
          style: TextStyle(color: palette.text, fontSize: 13),
          items: devices
              .map(
                (device) => DropdownMenuItem<String>(
                  value: device.id,
                  child: Text(
                    '${device.name}${device.connected ? '' : '（离线）'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: devices.isEmpty ? null : onChanged,
        ),
      ),
    );
  }
}

class _ModeOption extends StatefulWidget {
  const _ModeOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ModeOption> createState() => _ModeOptionState();
}

class _ModeOptionState extends State<_ModeOption> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    final color = widget.selected
        ? palette.selection
        : hovered && widget.enabled
        ? palette.surfaceHover
        : palette.surface;
    return Semantics(
      button: true,
      checked: widget.selected,
      enabled: widget.enabled,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 125),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 74),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hovered && widget.enabled
                    ? palette.strokeStrong
                    : palette.stroke,
              ),
            ),
            child: Row(
              children: <Widget>[
                _OutlineIcon(icon: widget.icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: widget.enabled
                              ? palette.text
                              : palette.textTertiary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.description,
                        style: TextStyle(
                          color: widget.enabled
                              ? palette.textSecondary
                              : palette.textTertiary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                _RadioMark(selected: widget.selected, enabled: widget.enabled),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineIcon extends StatelessWidget {
  const _OutlineIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return SizedBox(
      width: 30,
      child: Center(child: Icon(icon, size: 21, color: palette.textSecondary)),
    );
  }
}

class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 18,
      height: 18,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          width: 1.5,
          color: enabled
              ? (selected ? palette.indicator : palette.textTertiary)
              : palette.strokeStrong,
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? palette.indicator : Colors.transparent,
        ),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.controller});

  final AppController controller;

  String get endpointLabel {
    final status = controller.status;
    if (!status.connected) return '设备离线';
    if (controller.applyingMode) return '正在同步';
    if (controller.desiredMode == BluetoothAudioMode.a2dp) {
      return status.a2dpIsDefault ? 'A2DP 播放已就绪' : '配置未完成';
    }
    if (controller.desiredMode == BluetoothAudioMode.hfp) {
      return status.hfpCaptureIsDefault ? '通话输入已就绪' : '配置未完成';
    }
    return status.a2dpIsDefault && status.hfpCaptureIsDefault
        ? '播放与话筒已就绪'
        : '配置未完成';
  }

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final hfpLabel = !status.connected
        ? '设备离线'
        : status.hfpActive
        ? '活动中'
        : status.microphoneEnabled
        ? '未活动'
        : '话筒不可用';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _StatusPill(
          label: '当前配置',
          value: controller.effectiveModeLabel,
          active: status.connected,
        ),
        _StatusPill(label: 'HFP', value: hfpLabel, active: status.hfpActive),
        _StatusPill(
          label: '端点',
          value: endpointLabel,
          active: status.connected,
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? palette.blue : palette.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: palette.textTertiary, fontSize: 11),
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: TextStyle(
              color: palette.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneralPage extends StatelessWidget {
  const _GeneralPage({required this.controller, required this.showToast});

  final AppController controller;
  final ValueChanged<String> showToast;

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _PageHeading(title: '常规设置', subtitle: '调整应用的启动、后台与外观行为'),
          const _SectionTitle('启动与后台'),
          _SettingRow(
            icon: Icons.power_settings_new_rounded,
            title: '登录 Windows 后自动启动',
            description: '后台启动，仅驻留在任务栏通知区域',
            trailing: _WindowsSwitch(
              value: controller.launchAtStartupEnabled,
              onChanged: (enabled) async {
                await controller.setLaunchAtStartup(enabled);
                showToast(enabled ? '已开启登录后自动启动' : '已关闭登录后自动启动');
              },
            ),
          ),
          const SizedBox(height: 6),
          const _SettingRow(
            icon: Icons.web_asset_outlined,
            title: '关闭主窗口时',
            description: '应用继续在任务栏通知区域运行',
            trailing: _ValuePill('最小化到托盘'),
          ),
          const _SectionTitle('外观'),
          _SettingRow(
            icon: controller.darkThemeEnabled
                ? Icons.dark_mode_outlined
                : Icons.light_mode_outlined,
            title: '应用主题',
            description: '浅色与深色主题均采用 Windows 11 设置页样式',
            trailing: _ThemePicker(
              dark: controller.darkThemeEnabled,
              onChanged: (dark) async {
                await controller.setDarkTheme(dark);
                showToast(dark ? '已切换为深色主题' : '已切换为浅色主题');
              },
            ),
          ),
          if (controller.error != null) ...<Widget>[
            const SizedBox(height: 14),
            _ErrorBanner(message: controller.error!),
          ],
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return _HoverSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Row(
            children: <Widget>[
              _OutlineIcon(icon: icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                text,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: text),
              const SizedBox(width: 20),
              trailing,
            ],
          );
        },
      ),
    );
  }
}

class _WindowsSwitch extends StatefulWidget {
  const _WindowsSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_WindowsSwitch> createState() => _WindowsSwitchState();
}

class _WindowsSwitchState extends State<_WindowsSwitch> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    final track = widget.value ? palette.switchOnTrack : palette.control;
    final thumb = widget.value ? palette.switchOnThumb : palette.textSecondary;
    return Semantics(
      toggled: widget.value,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onChanged(!widget.value),
          child: SizedBox(
            width: 46,
            height: 28,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                width: 40,
                height: 20,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: widget.value
                        ? palette.switchOnTrack
                        : hovered
                        ? palette.textSecondary
                        : palette.strokeStrong,
                  ),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  alignment: widget.value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: thumb,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.dark, required this.onChanged});

  final bool dark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return Container(
      height: 36,
      width: 126,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: palette.strokeStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<bool>(
          value: dark,
          isExpanded: true,
          dropdownColor: palette.surface,
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: palette.textSecondary,
          ),
          style: TextStyle(color: palette.text, fontSize: 13),
          items: const <DropdownMenuItem<bool>>[
            DropdownMenuItem<bool>(value: true, child: Text('深色')),
            DropdownMenuItem<bool>(value: false, child: Text('浅色')),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.strokeStrong),
      ),
      child: Text(
        label,
        style: TextStyle(color: palette.textSecondary, fontSize: 12),
      ),
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return _PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _PageHeading(title: '关于', subtitle: '应用版本与工作方式'),
          const SizedBox(height: 26),
          _HoverSurface(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final icon = Container(
                  width: 68,
                  height: 68,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Image.asset(
                    'assets/app_icon_v4.png',
                    fit: BoxFit.contain,
                  ),
                );
                final copy = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '蓝牙音频模式切换器',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '版本 1.0.1 · Windows 11 x64',
                      style: TextStyle(
                        color: palette.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      '在 A2DP 高音质、HFP 通话与自动模式之间切换。应用根据 Windows ContainerId 关联同一耳机的音频端点，并在设备重新连接后恢复选定策略。',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                        height: 1.65,
                      ),
                    ),
                  ],
                );
                if (constraints.maxWidth < 460) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[icon, const SizedBox(height: 18), copy],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    icon,
                    const SizedBox(width: 20),
                    Expanded(child: copy),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverSurface extends StatefulWidget {
  const _HoverSurface({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 125),
        curve: Curves.easeOutCubic,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: hovered ? palette.surfaceHover : palette.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hovered ? palette.strokeStrong : palette.stroke,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF382627) : const Color(0xFFFFE8E8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: dark ? const Color(0xFF744245) : const Color(0xFFD8A3A3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 19,
            color: Color(0xFFD96A70),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: palette.text, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = _WinPalette.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: palette.strokeStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_rounded, size: 18, color: palette.success),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                message,
                style: TextStyle(color: palette.text, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
