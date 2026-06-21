import 'package:bluetooth_audio_manager/models.dart';
import 'package:test/test.dart';

void main() {
  group('BluetoothAudioMode', () {
    test('parses every wire value', () {
      for (final mode in BluetoothAudioMode.values) {
        expect(BluetoothAudioModeText.fromWire(mode.wireName), mode);
      }
    });

    test('unknown wire value is offline', () {
      expect(
        BluetoothAudioModeText.fromWire('unknown'),
        BluetoothAudioMode.offline,
      );
    });
  });

  test('device map keeps native endpoint identities', () {
    final device = BluetoothAudioDevice.fromMap(<Object?, Object?>{
      'id': '{container}',
      'name': 'AirPods Max',
      'connected': true,
      'a2dpEndpointId': 'a2dp',
      'hfpRenderEndpointId': 'hfp-render',
      'hfpCaptureEndpointId': 'hfp-capture',
      'hfpCaptureInstanceId': r'SWD\MMDEVAPI\{0.0.1}',
    });

    expect(device.id, '{container}');
    expect(device.connected, isTrue);
    expect(device.hfpCaptureInstanceId, startsWith(r'SWD\MMDEVAPI'));
  });

  test('status map reports mixed configuration without coercing mode', () {
    final status = BluetoothAudioStatus.fromMap(<Object?, Object?>{
      'mode': 'mixed',
      'connected': true,
      'microphoneEnabled': true,
      'hfpActive': true,
      'a2dpIsDefault': true,
      'hfpRenderIsDefault': false,
      'hfpCaptureIsDefault': true,
    });

    expect(status.mode, BluetoothAudioMode.mixed);
    expect(status.microphoneEnabled, isTrue);
    expect(status.hfpActive, isTrue);
    expect(status.a2dpIsDefault, isTrue);
  });

  test('offline status does not report HFP activity', () {
    expect(BluetoothAudioStatus.offline.hfpActive, isFalse);
  });

  group('tray toggle target', () {
    test('uses configured binary mode', () {
      expect(
        trayToggleTarget(BluetoothAudioMode.hfp, BluetoothAudioMode.hfp),
        BluetoothAudioMode.a2dp,
      );
      expect(
        trayToggleTarget(BluetoothAudioMode.a2dp, BluetoothAudioMode.a2dp),
        BluetoothAudioMode.hfp,
      );
    });

    test('uses desired mode for mixed and offline states', () {
      expect(
        trayToggleTarget(BluetoothAudioMode.mixed, BluetoothAudioMode.hfp),
        BluetoothAudioMode.a2dp,
      );
      expect(
        trayToggleTarget(BluetoothAudioMode.offline, BluetoothAudioMode.a2dp),
        BluetoothAudioMode.hfp,
      );
    });
  });
}
