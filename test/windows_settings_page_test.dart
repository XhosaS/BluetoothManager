import 'dart:async';

import 'package:bluetooth_audio_manager/app_controller.dart';
import 'package:bluetooth_audio_manager/bluetooth_audio_platform.dart';
import 'package:bluetooth_audio_manager/models.dart';
import 'package:bluetooth_audio_manager/windows_settings_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppController controller;

  setUp(() {
    const device = BluetoothAudioDevice(
      id: '{test-container}',
      name: "耳机 (Xhosa's AirPods Max)",
      connected: true,
      a2dpEndpointId: 'a2dp',
      hfpRenderEndpointId: 'hfp-render',
      hfpCaptureEndpointId: 'hfp-capture',
      hfpCaptureInstanceId: 'hfp-instance',
    );
    controller = AppController()
      ..devices = const <BluetoothAudioDevice>[device]
      ..selectedDevice = device
      ..desiredMode = BluetoothAudioMode.automatic
      ..status = const BluetoothAudioStatus(
        mode: BluetoothAudioMode.hfp,
        connected: true,
        microphoneEnabled: true,
        hfpActive: false,
        a2dpIsDefault: true,
        hfpRenderIsDefault: false,
        hfpCaptureIsDefault: true,
      )
      ..loading = false;
  });

  tearDown(() => controller.dispose());

  testWidgets('audio page has no layout exceptions at supported window sizes', (
    tester,
  ) async {
    for (final entry in <String, Size>{
      'audio-680x540-dark': const Size(680, 540),
      'audio-980x720-dark': const Size(980, 720),
      'audio-1280x760-dark': const Size(1280, 760),
    }.entries) {
      await _pumpAtSize(
        tester,
        controller: controller,
        size: entry.value,
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull, reason: entry.key);
      expect(find.text("耳机 (Xhosa's AirPods Max)"), findsOneWidget);
      expect(find.text('自动模式'), findsOneWidget);
      expect(find.text('端口'), findsOneWidget);
      expect(find.text('端点'), findsNothing);
    }
  });

  testWidgets('minimum window settings page fits in dark and light themes', (
    tester,
  ) async {
    for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
      await _pumpAtSize(
        tester,
        controller: controller,
        size: const Size(680, 540),
        brightness: brightness,
      );
      await tester.tap(find.text('常规设置').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('登录 Windows 后自动启动'), findsOneWidget);
      expect(find.text('最小化到托盘'), findsOneWidget);
      expect(find.text('浅色与深色主题均采用 Windows 11 设置页样式'), findsNothing);
      expect(
        find.text(brightness == Brightness.dark ? '深色' : '浅色'),
        findsOneWidget,
      );
    }
  });

  testWidgets('sidebar version aligns with the About label', (tester) async {
    await _pumpAtSize(
      tester,
      controller: controller,
      size: const Size(980, 720),
      brightness: Brightness.dark,
    );

    final aboutX = tester.getTopLeft(find.text('关于')).dx;
    final versionX = tester.getTopLeft(find.text('版本 1.0.2')).dx;
    expect(versionX, closeTo(aboutX, 0.01));
  });

  testWidgets('hover changes styling without moving mode text', (tester) async {
    await _pumpAtSize(
      tester,
      controller: controller,
      size: const Size(980, 720),
      brightness: Brightness.dark,
    );
    final title = find.text('A2DP 高音质');
    final before = tester.getTopLeft(title);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(title));
    await tester.pump(const Duration(milliseconds: 160));
    final after = tester.getTopLeft(title);
    expect(after, before);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  testWidgets('enabled switch uses the Windows reference colors', (
    tester,
  ) async {
    for (final entry in <Brightness, ({Color track, Color thumb})>{
      Brightness.dark: (
        track: const Color(0xFF5B5B5B),
        thumb: const Color(0xFF080808),
      ),
      Brightness.light: (
        track: const Color(0xFF5D5D5D),
        thumb: const Color(0xFFFFFFFF),
      ),
    }.entries) {
      await _pumpAtSize(
        tester,
        controller: controller,
        size: const Size(680, 540),
        brightness: entry.key,
      );
      await tester.tap(find.text('常规设置').first);
      await tester.pumpAndSettle();

      final trackFinder = find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedContainer &&
            widget.constraints?.minWidth == 40 &&
            widget.constraints?.maxWidth == 40 &&
            widget.constraints?.minHeight == 20 &&
            widget.constraints?.maxHeight == 20,
      );
      expect(trackFinder, findsOneWidget);
      final track = tester.widget<AnimatedContainer>(trackFinder);
      expect((track.decoration! as BoxDecoration).color, entry.value.track);

      final thumbFinder = find.descendant(
        of: trackFinder,
        matching: find.byType(Container),
      );
      expect(thumbFinder, findsNWidgets(2));
      final thumb = tester.widget<Container>(thumbFinder.last);
      expect((thumb.decoration! as BoxDecoration).color, entry.value.thumb);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('minimum audio page remains scrollable without overflow', (
    tester,
  ) async {
    await _pumpAtSize(
      tester,
      controller: controller,
      size: const Size(680, 540),
      brightness: Brightness.dark,
    );
    final scrollView = find.byType(SingleChildScrollView).first;
    await tester.drag(scrollView, const Offset(0, -360));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('当前状态'), findsOneWidget);
  });

  testWidgets(
    'mode change keeps UI responsive and updates toast asynchronously',
    (tester) async {
      final platform = _PendingModePlatform();
      final asyncController = AppController(platform: platform)
        ..devices = controller.devices
        ..selectedDevice = controller.selectedDevice
        ..desiredMode = BluetoothAudioMode.automatic
        ..status = controller.status
        ..loading = false;
      addTearDown(asyncController.dispose);

      await _pumpAtSize(
        tester,
        controller: asyncController,
        size: const Size(980, 720),
        brightness: Brightness.dark,
      );
      await tester.tap(find.text('A2DP 高音质'));
      await tester.pump();

      expect(find.text('正在切换到A2DP 高音质…'), findsOneWidget);
      expect(asyncController.applyingMode, isTrue);

      await tester.tap(find.text('常规设置').first);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('登录 Windows 后自动启动'), findsOneWidget);

      platform.complete(controller.status);
      await tester.pump();
      expect(find.text('已切换到A2DP 高音质'), findsOneWidget);
      expect(asyncController.applyingMode, isFalse);
    },
  );
}

class _PendingModePlatform extends BluetoothAudioPlatform {
  final Completer<BluetoothAudioStatus> _mode =
      Completer<BluetoothAudioStatus>();

  @override
  Future<BluetoothAudioStatus> setMode(
    String deviceId,
    BluetoothAudioMode mode,
  ) => _mode.future;

  void complete(BluetoothAudioStatus status) => _mode.complete(status);
}

Future<void> _pumpAtSize(
  WidgetTester tester, {
  required AppController controller,
  required Size size,
  required Brightness brightness,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  controller.darkThemeEnabled = brightness == Brightness.dark;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: brightness,
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei UI',
      ),
      home: WindowsSettingsPage(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}
