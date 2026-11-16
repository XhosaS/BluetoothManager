import 'dart:async';

import 'package:bluetooth_audio_manager/app_controller.dart';
import 'package:bluetooth_audio_manager/bluetooth_audio_platform.dart';
import 'package:bluetooth_audio_manager/models.dart';
import 'package:flutter_test/flutter_test.dart';

const device = BluetoothAudioDevice(
  id: 'selected-container',
  name: 'Selected headset',
  connected: true,
  a2dpEndpointId: 'music',
  hfpRenderEndpointId: 'voice',
  hfpCaptureEndpointId: 'mic',
  hfpCaptureInstanceId: 'mic-pnp',
);
const connected = BluetoothAudioStatus(
  mode: BluetoothAudioMode.a2dp,
  connected: true,
  microphoneEnabled: false,
  hfpActive: false,
  a2dpIsDefault: true,
  hfpRenderIsDefault: false,
  hfpCaptureIsDefault: false,
);

class ReconnectPlatform extends BluetoothAudioPlatform {
  final completion = Completer<BluetoothAudioStatus>();
  int calls = 0;
  int modeCalls = 0;
  String? target;
  BluetoothAudioMode? requested;
  @override
  Future<BluetoothAudioStatus> reconnect(String id, BluetoothAudioMode mode) {
    calls++;
    target = id;
    requested = mode;
    return completion.future;
  }

  @override
  Future<List<BluetoothAudioDevice>> listDevices() async => [device];
  @override
  Future<BluetoothAudioStatus> getStatus(String id) async => connected;
  @override
  Future<void> watchDevice(String id) async {}
  @override
  Future<BluetoothAudioStatus> setMode(
    String id,
    BluetoothAudioMode mode,
  ) async {
    modeCalls++;
    return connected;
  }
}

void main() {
  test(
    'resume rechecks a connected headset without cycling its connection',
    () async {
      final platform = ReconnectPlatform();
      final controller = AppController(platform: platform)
        ..selectedDevice = device
        ..desiredMode = BluetoothAudioMode.automatic
        ..status = connected;
      await controller.refresh(reapplyDesiredMode: true, afterResume: true);
      expect(platform.modeCalls, 1);
      expect(platform.calls, 0);
      controller.dispose();
    },
  );
  test(
    'reconnect targets selected headset, preserves mode and excludes overlap',
    () async {
      final platform = ReconnectPlatform();
      final controller = AppController(platform: platform)
        ..selectedDevice = device
        ..devices = [device]
        ..desiredMode = BluetoothAudioMode.automatic
        ..status = connected;
      final operation = controller.reconnect();
      expect(controller.reconnecting, isTrue);
      await controller.reconnect();
      await controller.setMode(BluetoothAudioMode.hfp);
      expect(platform.calls, 1);
      expect(platform.target, device.id);
      expect(platform.requested, BluetoothAudioMode.automatic);
      platform.completion.complete(connected);
      await operation;
      expect(controller.applyingMode, isFalse);
      expect(controller.reconnecting, isFalse);
      expect(controller.desiredMode, BluetoothAudioMode.automatic);
      controller.dispose();
    },
  );

  test(
    'reconnect preserves actionable failure after refreshing status',
    () async {
      final platform = ReconnectPlatform();
      final controller = AppController(platform: platform)
        ..selectedDevice = device
        ..status = connected;
      final operation = controller.reconnect();
      platform.completion.completeError(
        const BluetoothAudioException('denied', '请在蓝牙设置中重新连接'),
      );
      await operation;
      expect(controller.error, '请在蓝牙设置中重新连接');
      expect(controller.applyingMode, isFalse);
      expect(controller.status.connected, isTrue);
      controller.dispose();
    },
  );

  test('active microphone blocks reconnect', () async {
    final platform = ReconnectPlatform();
    final controller = AppController(platform: platform)
      ..selectedDevice = device
      ..status = const BluetoothAudioStatus(
        mode: BluetoothAudioMode.hfp,
        connected: true,
        microphoneEnabled: true,
        hfpActive: true,
        a2dpIsDefault: true,
        hfpRenderIsDefault: true,
        hfpCaptureIsDefault: true,
      );
    await controller.reconnect();
    expect(platform.calls, 0);
    expect(controller.error, contains('结束通话'));
    controller.dispose();
  });
}
