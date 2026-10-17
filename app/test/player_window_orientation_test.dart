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
