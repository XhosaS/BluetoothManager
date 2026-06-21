import 'package:flutter/services.dart';

import 'models.dart';

class BluetoothAudioException implements Exception {
  const BluetoothAudioException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}

class BluetoothAudioPlatform {
  const BluetoothAudioPlatform();

  static const MethodChannel _channel = MethodChannel(
    'com.xhosa.bluetooth_audio_manager/audio',
  );

  Future<List<BluetoothAudioDevice>> listDevices() async {
    try {
      final values = await _channel.invokeListMethod<Object?>('listDevices');
      return (values ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(BluetoothAudioDevice.fromMap)
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw BluetoothAudioException(error.code, error.message ?? '无法枚举蓝牙音频设备');
    }
  }

  Future<BluetoothAudioStatus> getStatus(String deviceId) async {
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'getStatus',
        <String, Object?>{'deviceId': deviceId},
      );
      return BluetoothAudioStatus.fromMap(value ?? const {});
    } on PlatformException catch (error) {
      throw BluetoothAudioException(error.code, error.message ?? '无法读取音频模式');
    }
  }

  Future<BluetoothAudioStatus> setMode(
    String deviceId,
    BluetoothAudioMode mode,
  ) async {
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'setMode',
        <String, Object?>{'deviceId': deviceId, 'mode': mode.wireName},
      );
      return BluetoothAudioStatus.fromMap(value ?? const {});
    } on PlatformException catch (error) {
      throw BluetoothAudioException(error.code, error.message ?? '切换音频模式失败');
    }
  }

  Future<void> setLaunchAtStartup(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setLaunchAtStartup', <String, Object?>{
        'enabled': enabled,
      });
    } on PlatformException catch (error) {
      throw BluetoothAudioException(error.code, error.message ?? '无法修改开机启动设置');
    }
  }
}
