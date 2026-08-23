import 'dart:ui';

import 'package:bluetooth_audio_manager/window_size.dart';
import 'package:test/test.dart';

void main() {
  test('uses the normal application size without a QA override', () {
    expect(initialWindowSize(const <String>[]), const Size(980, 720));
  });

  test('accepts each responsive QA window size', () {
    expect(
      initialWindowSize(const <String>['--window-size=680x540']),
      const Size(680, 540),
    );
    expect(
      initialWindowSize(const <String>['--window-size=1280x760']),
      const Size(1280, 760),
    );
  });

  test('clamps QA sizes to supported bounds', () {
    expect(
      initialWindowSize(const <String>['--window-size=320x200']),
      const Size(680, 540),
    );
    expect(
      initialWindowSize(const <String>['--window-size=9999x9999']),
      const Size(2400, 1600),
    );
  });
}
