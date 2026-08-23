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

  group('tray mode menu', () {
    test('maps each mode command directly to its policy', () {
      expect(trayModeFromMenuKey('mode_a2dp'), BluetoothAudioMode.a2dp);
      expect(trayModeFromMenuKey('mode_hfp'), BluetoothAudioMode.hfp);
      expect(
        trayModeFromMenuKey('mode_automatic'),
        BluetoothAudioMode.automatic,
      );
    });

    test('ignores unrelated menu commands', () {
      expect(trayModeFromMenuKey('exit'), isNull);
      expect(trayModeFromMenuKey(null), isNull);
    });

    test('checks only the desired policy, including automatic mode', () {
      expect(
        isTrayModeSelected(BluetoothAudioMode.automatic, 'mode_automatic'),
        isTrue,
      );
      expect(
        isTrayModeSelected(BluetoothAudioMode.automatic, 'mode_a2dp'),
        isFalse,
      );
      expect(
        isTrayModeSelected(BluetoothAudioMode.automatic, 'mode_hfp'),
        isFalse,
      );
    });
  });

  group('automatic mode', () {
    const ready = BluetoothAudioStatus(
      mode: BluetoothAudioMode.hfp,
      connected: true,
      microphoneEnabled: true,
      hfpActive: false,
      a2dpIsDefault: true,
      hfpRenderIsDefault: false,
      hfpCaptureIsDefault: true,
    );

    test('accepts the HFP-ready unified endpoint configuration', () {
      expect(ready.isCompatibleWith(BluetoothAudioMode.automatic), isTrue);
    });

    test('reports A2DP while idle and HFP while capture is active', () {
      expect(
        ready.effectiveMode(BluetoothAudioMode.automatic),
        BluetoothAudioMode.a2dp,
      );
      final active = BluetoothAudioStatus.fromMap(<Object?, Object?>{
        'mode': 'hfp',
        'connected': true,
        'microphoneEnabled': true,
        'hfpActive': true,
        'a2dpIsDefault': true,
        'hfpCaptureIsDefault': true,
      });
      expect(
        active.effectiveMode(BluetoothAudioMode.automatic),
        BluetoothAudioMode.hfp,
      );
    });
  });
}
