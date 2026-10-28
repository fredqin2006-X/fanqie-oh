import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/platform/player_gesture_device.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fqapp/display');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late PlayerGestureDevice device;

  setUp(() {
    calls = [];
    device = PlayerGestureDevice();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'beginPlayerBrightness') return 0.4;
      if (call.method == 'setPlayerBrightness') return true;
      return null;
    });
  });
  tearDown(() async {
    await device.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('one lease uses bounded brightness and ends once', () async {
    expect(await device.begin(), 0.4);
    expect(await device.begin(), 0.4);
    expect(await device.setBrightness(-2), true);
    expect(calls.last.arguments['brightness'], 0.02);
    expect(await device.setBrightness(double.nan), false);
    await device.dispose();
    await device.dispose();
    expect(calls.map((c) => c.method), [
      'beginPlayerBrightness',
      'setPlayerBrightness',
      'endPlayerBrightness',
    ]);
    expect(calls.map((c) => c.arguments['session']).toSet(), hasLength(1));
    expect(await device.begin(), isNull);
  });

  test('missing bridge can recover on a subsequent begin', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await device.begin(), isNull);
    expect(await device.setBrightness(0.8), false);
    messenger.setMockMethodCallHandler(channel, (_) async => 0.6);
    expect(await device.begin(), 0.6);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });

  test(
    'invalid initial brightness releases its lease and permits retry',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'beginPlayerBrightness' ? 3.0 : null;
      });
      expect(await device.begin(), isNull);
      expect(calls.last.method, 'endPlayerBrightness');
      expect(await device.setBrightness(0.7), false);
    },
  );

  test(
    'suspend invalidates a delayed begin without affecting new lease',
    () async {
      final gate = Completer<double>();
      var begins = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'beginPlayerBrightness') {
          return ++begins == 1 ? gate.future : 0.7;
        }
        return null;
      });
      final first = device.begin();
      await Future<void>.delayed(Duration.zero);
      await device.suspend();
      expect(await device.begin(), 0.7);
      gate.complete(0.3);
      expect(await first, isNull);
      expect(await device.begin(), 0.7);
      expect(
        calls.first.arguments['session'],
        isNot(calls.last.arguments['session']),
      );
    },
  );

  test(
    'out of order brightness acknowledgements preserve newest value',
    () async {
      final gates = [Completer<bool>(), Completer<bool>()];
      var writes = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'beginPlayerBrightness') return 0.4;
        if (call.method == 'setPlayerBrightness') return gates[writes++].future;
        return null;
      });
      await device.begin();
      final old = device.setBrightness(0.3);
      final latest = device.setBrightness(0.8);
      await Future<void>.delayed(Duration.zero);
      gates[1].complete(true);
      expect(await latest, true);
      gates[0].complete(true);
      expect(await old, true);
      expect(await device.begin(), 0.8);
    },
  );

  test('a retired native lease can be acquired again', () async {
    var accepts = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'beginPlayerBrightness') return 0.5;
      if (call.method == 'setPlayerBrightness') return accepts;
      return null;
    });
    await device.begin();
    final firstSession = calls.first.arguments['session'];
    expect(await device.setBrightness(0.8), false);
    expect(calls.last.method, 'endPlayerBrightness');
    accepts = true;
    expect(await device.begin(), 0.5);
    expect(calls.last.arguments['session'], isNot(firstSession));
    expect(await device.setBrightness(0.8), true);
    expect(await device.begin(), 0.8);
  });

  test('dispose invalidates a shared pending begin and closes once', () async {
    final gate = Completer<double>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'beginPlayerBrightness' ? gate.future : null;
    });
    final first = device.begin();
    final second = device.begin();
    expect(identical(first, second), true);
    await Future<void>.delayed(Duration.zero);
    await device.dispose();
    gate.complete(0.4);
    expect(await first, isNull);
    expect(await second, isNull);
    expect(await device.setBrightness(0.7), false);
    expect(calls.map((call) => call.method), [
      'beginPlayerBrightness',
      'endPlayerBrightness',
    ]);
  });

  test('late writes cannot overwrite a resumed session', () async {
    final gate = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'beginPlayerBrightness') return 0.4;
      if (call.method == 'setPlayerBrightness') return gate.future;
      return null;
    });
    await device.begin();
    final pending = device.setBrightness(0.9);
    await Future<void>.delayed(Duration.zero);
    await device.suspend();
    expect(await device.begin(), 0.4);
    gate.complete(true);
    expect(await pending, false);
    expect(await device.begin(), 0.4);
  });

  test(
    'platform failure releases a partially opened lease and retries',
    () async {
      var fails = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'beginPlayerBrightness') {
          if (fails) throw PlatformException(code: 'WINDOW_UNAVAILABLE');
          return 0.3;
        }
        return null;
      });
      expect(await device.begin(), isNull);
      expect(calls.last.method, 'endPlayerBrightness');
      fails = false;
      expect(await device.begin(), 0.3);
    },
  );
}
