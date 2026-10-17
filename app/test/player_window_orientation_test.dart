import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/platform/player_window_orientation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const display = MethodChannel('fqapp/display');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(display, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
    'Harmony fullscreen acknowledges before late rotation and back',
    () async {
      final calls = <String>[];
      final overlays = <Object?>[];
      final neverReplies = Completer<Object?>();
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          // Reproduce the embedding's missing success reply. Using this method
          // would leave this sequence pending rather than reaching rotation.
          return neverReplies.future;
        }
        calls.add(call.method);
        overlays.add(call.arguments);
        return null;
      });
      messenger.setMockMethodCallHandler(display, (call) async {
        calls.add((call.arguments as Map)['orientation'] as String);
        return null;
      });
      const orientation = PlayerWindowOrientation(harmony: true);
      await orientation.setFullscreen(true).timeout(const Duration(seconds: 1));
      await orientation.set(DeviceOrientation.landscapeLeft);
      await orientation.set(null);
      await orientation
          .setFullscreen(false)
          .timeout(const Duration(seconds: 1));
      expect(calls, [
        'SystemChrome.setEnabledSystemUIOverlays',
        'landscape',
        'restore',
        'SystemChrome.setEnabledSystemUIOverlays',
      ]);
      expect(overlays, [
        [],
        ['SystemUiOverlay.top', 'SystemUiOverlay.bottom'],
      ]);
    },
  );

  test(
    'Harmony uses fixed native orientations and restores the window policy',
    () async {
      final requests = <String>[];
      messenger.setMockMethodCallHandler(display, (call) async {
        expect(call.method, 'setOrientation');
        requests.add((call.arguments as Map)['orientation'] as String);
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        fail(
          'Native orientation should not depend on the Flutter system UI channel',
        );
      });
      const orientation = PlayerWindowOrientation(harmony: true);
      await orientation.set(DeviceOrientation.landscapeLeft);
      await orientation.set(DeviceOrientation.portraitUp);
      await orientation.set(null);
      expect(requests, ['landscape', 'portrait', 'restore']);
    },
  );

  test(
    'an older embedding falls back, but native orientation errors propagate',
    () async {
      final fallback = <Object?>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          fallback.add(call.arguments);
        }
        return null;
      });
      const orientation = PlayerWindowOrientation(harmony: true);
      await orientation.set(DeviceOrientation.landscapeLeft);
      expect(fallback, [
        ['DeviceOrientation.landscapeLeft'],
      ]);
      messenger.setMockMethodCallHandler(display, (call) async {
        throw PlatformException(code: 'ORIENTATION_FAILED');
      });
      await expectLater(
        orientation.set(DeviceOrientation.portraitUp),
        throwsA(isA<PlatformException>()),
      );
      expect(fallback, hasLength(1));
    },
  );
}
