enum BluetoothAudioMode { a2dp, hfp, automatic, mixed, offline }

BluetoothAudioMode trayToggleTarget(BluetoothAudioMode desiredMode) {
  // The tray action cycles policies rather than the native configuration.
  // In automatic mode the native configuration intentionally remains HFP-ready.
  return switch (desiredMode) {
    BluetoothAudioMode.a2dp => BluetoothAudioMode.hfp,
    BluetoothAudioMode.hfp => BluetoothAudioMode.automatic,
    BluetoothAudioMode.automatic => BluetoothAudioMode.a2dp,
    BluetoothAudioMode.mixed ||
    BluetoothAudioMode.offline => BluetoothAudioMode.a2dp,
  };
}

extension BluetoothAudioModeText on BluetoothAudioMode {
  String get label => switch (this) {
    BluetoothAudioMode.a2dp => 'A2DP 高音质',
    BluetoothAudioMode.hfp => 'HFP 通话',
    BluetoothAudioMode.automatic => '自动模式',
    BluetoothAudioMode.mixed => '混合状态',
    BluetoothAudioMode.offline => '设备离线',
  };

  String get wireName => name;

  String get switchActionLabel => switch (this) {
    BluetoothAudioMode.a2dp => '切换到 A2DP',
    BluetoothAudioMode.hfp => '切换到 HFP',
    BluetoothAudioMode.automatic => '切换到自动模式',
    BluetoothAudioMode.mixed || BluetoothAudioMode.offline => '切换模式',
  };

  static BluetoothAudioMode fromWire(String? value) =>
      BluetoothAudioMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => BluetoothAudioMode.offline,
      );
}

class BluetoothAudioDevice {
  const BluetoothAudioDevice({
    required this.id,
    required this.name,
    required this.connected,
    required this.a2dpEndpointId,
    required this.hfpRenderEndpointId,
    required this.hfpCaptureEndpointId,
    required this.hfpCaptureInstanceId,
  });

  final String id;
  final String name;
  final bool connected;
  final String a2dpEndpointId;
  final String hfpRenderEndpointId;
  final String hfpCaptureEndpointId;
  final String hfpCaptureInstanceId;

  factory BluetoothAudioDevice.fromMap(Map<Object?, Object?> map) {
    String text(String key) => map[key]?.toString() ?? '';
    return BluetoothAudioDevice(
      id: text('id'),
      name: text('name'),
      connected: map['connected'] == true,
      a2dpEndpointId: text('a2dpEndpointId'),
      hfpRenderEndpointId: text('hfpRenderEndpointId'),
      hfpCaptureEndpointId: text('hfpCaptureEndpointId'),
      hfpCaptureInstanceId: text('hfpCaptureInstanceId'),
    );
  }
}

class BluetoothAudioStatus {
  const BluetoothAudioStatus({
    required this.mode,
    required this.connected,
    required this.microphoneEnabled,
    required this.hfpActive,
    required this.a2dpIsDefault,
    required this.hfpRenderIsDefault,
    required this.hfpCaptureIsDefault,
  });

  final BluetoothAudioMode mode;
  final bool connected;
  final bool microphoneEnabled;
  final bool hfpActive;
  final bool a2dpIsDefault;
  final bool hfpRenderIsDefault;
  final bool hfpCaptureIsDefault;

  bool isCompatibleWith(
    BluetoothAudioMode desiredMode,
  ) => switch (desiredMode) {
    BluetoothAudioMode.automatic =>
      connected && microphoneEnabled && a2dpIsDefault && hfpCaptureIsDefault,
    BluetoothAudioMode.a2dp || BluetoothAudioMode.hfp => mode == desiredMode,
    BluetoothAudioMode.mixed || BluetoothAudioMode.offline => false,
  };

  BluetoothAudioMode effectiveMode(BluetoothAudioMode desiredMode) {
    if (!connected) return BluetoothAudioMode.offline;
    if (desiredMode == BluetoothAudioMode.automatic) {
      return hfpActive ? BluetoothAudioMode.hfp : BluetoothAudioMode.a2dp;
    }
    return mode;
  }

  factory BluetoothAudioStatus.fromMap(Map<Object?, Object?> map) =>
      BluetoothAudioStatus(
        mode: BluetoothAudioModeText.fromWire(map['mode']?.toString()),
        connected: map['connected'] == true,
        microphoneEnabled: map['microphoneEnabled'] == true,
        hfpActive: map['hfpActive'] == true,
        a2dpIsDefault: map['a2dpIsDefault'] == true,
        hfpRenderIsDefault: map['hfpRenderIsDefault'] == true,
        hfpCaptureIsDefault: map['hfpCaptureIsDefault'] == true,
      );

  static const offline = BluetoothAudioStatus(
    mode: BluetoothAudioMode.offline,
    connected: false,
    microphoneEnabled: false,
    hfpActive: false,
    a2dpIsDefault: false,
    hfpRenderIsDefault: false,
    hfpCaptureIsDefault: false,
  );
}
