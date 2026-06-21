import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_audio_platform.dart';
import 'models.dart';

class AppController extends ChangeNotifier {
  AppController({this.platform = const BluetoothAudioPlatform()});

  static const _selectedDeviceKey = 'selected_device_id';
  static const _desiredModeKey = 'desired_mode';
  static const _launchAtStartupKey = 'launch_at_startup';

  final BluetoothAudioPlatform platform;
  SharedPreferences? _preferences;
  Timer? _pollTimer;
  bool _refreshing = false;
  bool _applyingMode = false;

  List<BluetoothAudioDevice> devices = const [];
  BluetoothAudioDevice? selectedDevice;
  BluetoothAudioStatus status = BluetoothAudioStatus.offline;
  BluetoothAudioMode desiredMode = BluetoothAudioMode.a2dp;
  bool launchAtStartupEnabled = true;
  bool loading = true;
  String? error;

  bool get applyingMode => _applyingMode;

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    desiredMode = BluetoothAudioModeText.fromWire(
      _preferences!.getString(_desiredModeKey),
    );
    if (desiredMode != BluetoothAudioMode.hfp) {
      desiredMode = BluetoothAudioMode.a2dp;
    }
    launchAtStartupEnabled = _preferences!.getBool(_launchAtStartupKey) ?? true;
    await refresh(reapplyDesiredMode: true);
    if (launchAtStartupEnabled) {
      await _setStartupRegistration(true, reportError: true);
    }
    loading = false;
    notifyListeners();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => refresh(reapplyDesiredMode: true),
    );
  }

  Future<void> refresh({bool reapplyDesiredMode = false}) async {
    if (_refreshing || _applyingMode) return;
    _refreshing = true;
    try {
      final previousConnected = selectedDevice?.connected ?? false;
      devices = await platform.listDevices();
      final selectedId =
          selectedDevice?.id ?? _preferences?.getString(_selectedDeviceKey);
      selectedDevice =
          _findDevice(selectedId) ?? (devices.isEmpty ? null : devices.first);
      final device = selectedDevice;
      if (device == null) {
        status = BluetoothAudioStatus.offline;
      } else {
        await _preferences?.setString(_selectedDeviceKey, device.id);
        status = await platform.getStatus(device.id);
        if (reapplyDesiredMode &&
            !previousConnected &&
            device.connected &&
            status.mode != desiredMode) {
          _refreshing = false;
          await setMode(desiredMode);
          return;
        }
      }
      error = null;
    } catch (exception) {
      error = exception.toString();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  BluetoothAudioDevice? _findDevice(String? id) {
    if (id == null) return null;
    for (final device in devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  Future<void> selectDevice(String? id) async {
    final device = _findDevice(id);
    if (device == null) return;
    selectedDevice = device;
    await _preferences?.setString(_selectedDeviceKey, device.id);
    await refresh();
  }

  Future<void> setMode(BluetoothAudioMode mode) async {
    if (_applyingMode ||
        (mode != BluetoothAudioMode.a2dp && mode != BluetoothAudioMode.hfp)) {
      return;
    }
    desiredMode = mode;
    await _preferences?.setString(_desiredModeKey, mode.wireName);
    final device = selectedDevice;
    if (device == null || !device.connected) {
      status = BluetoothAudioStatus.offline;
      notifyListeners();
      return;
    }
    _applyingMode = true;
    error = null;
    notifyListeners();
    try {
      status = await platform.setMode(device.id, mode);
    } catch (exception) {
      error = exception.toString();
    } finally {
      _applyingMode = false;
      notifyListeners();
    }
  }

  Future<void> setLaunchAtStartup(bool enabled) async {
    launchAtStartupEnabled = enabled;
    await _preferences?.setBool(_launchAtStartupKey, enabled);
    await _setStartupRegistration(enabled, reportError: true);
    notifyListeners();
  }

  Future<void> _setStartupRegistration(
    bool enabled, {
    required bool reportError,
  }) async {
    try {
      await platform.setLaunchAtStartup(enabled);
    } catch (exception) {
      if (reportError) error = '无法修改开机启动设置：$exception';
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
