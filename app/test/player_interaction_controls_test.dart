import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fqapp/services/player_style_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/widgets/video_player_chrome.dart';

import 'support/fakes.dart';

void main() {
  late List<MethodCall> nativeCalls;
  late List<MethodCall> displayCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({'player_playback_rate': 1.5});
    // 面板交互用例钉住深色分支（play_control_panel_style_v681.style=1）：
    // 药丸拖选/取消行是深色面板独有的交互，浅色分支另有用例覆盖。
    PlayerStyleConfig.instance = const PlayerStyleConfig(
      useNewPlayerBottomStyle: true,
      morePanelStyle: 1,
    );
    nativeCalls = [];
    displayCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('fqapp/display'), (
          call,
        ) async {
          displayCalls.add(call);
          return switch (call.method) {
            'beginPlayerBrightness' => .5,
            'setPlayerBrightness' => true,
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('fqapp/native_player'), (
          call,
        ) async {
          nativeCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    PlayerStyleConfig.instance = PlayerStyleConfig.defaults;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('fqapp/display'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fqapp/native_player'),
          null,
        );
  });

  testWidgets('clear screen survives pause, resume and the auto-hide timeout', (
    tester,
  ) async {
    final player = FakeNativePlayer()..isPlaying = true;
    final selected = <int>[];
    await _mount(tester, player, selected: selected, shortSeries: true);
    expect(find.byKey(const ValueKey('video-seek')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('player-clear-screen')));
    await tester.pump();
    _expectClearScreen();
    // 手势仍操作播放器，清屏状态独立于暂停反馈和自动收起计时器。
    await tester.tapAt(const Offset(40, 400));
    // 官方竖屏注册了双击点赞，单击要等双击窗口（800ms）结束才确认。
    await tester.pump(const Duration(milliseconds: 850));
    expect(player.isPlaying, isFalse);
    _expectClearScreen();
    await tester.tapAt(const Offset(40, 400));
    await tester.pump(const Duration(milliseconds: 850));
    expect(player.isPlaying, isTrue);
    await tester.pump(const Duration(seconds: 4));
    _expectClearScreen();
    expect(selected, isEmpty);
    await tester.tap(find.text('恢复'));
    await tester.pump();
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-seek')), findsOneWidget);
    expect(find.text('恢复'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear screen keeps long press and speed selection working', (
    tester,
  ) async {
    final player = FakeNativePlayer()..isPlaying = true;
    await _mount(tester, player, shortSeries: true);
    await tester.tap(find.byKey(const ValueKey('player-clear-screen')));
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(40, 400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(player.rate, 2);
    await gesture.up();
    await tester.pump();
    expect(player.rate, 1.5);
    await tester.pump(const Duration(seconds: 4));
    _expectClearScreen();

    await tester.tap(find.byKey(const ValueKey('player-rate-text')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-rate-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-clear-screen')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('player-rate-sheet-2')));
    await tester.pumpAndSettle();
    expect(player.rate, 1.25);
    expect(find.text('1.25x'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    _expectClearScreen();
  });

  testWidgets('clear screen survives paging, loading and player replacement', (
    tester,
  ) async {
    final first = FakeNativePlayer()..isPlaying = true;
    final second = FakeNativePlayer()..isPlaying = true;
    final selected = <int>[];
    await _mount(tester, first, shortSeries: true, selected: selected);
    addTearDown(second.dispose);
    await tester.tap(find.byKey(const ValueKey('player-clear-screen')));
    await tester.pump();
    await tester.dragFrom(const Offset(160, 400), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(selected, contains(1));
    await tester.pump(const Duration(seconds: 4));
    _expectClearScreen();

    await tester.pumpWidget(
      _app(first, index: 1, enabled: false, shortSeries: true),
    );
    await tester.pump();
    _expectClearScreen();
    await tester.pumpWidget(_app(second, index: 1, shortSeries: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    _expectClearScreen();
    await tester.tap(find.text('恢复'));
    await tester.pump();
    expect(find.byKey(const ValueKey('video-seek')), findsOneWidget);
    expect(find.text('第2集'), findsOneWidget);
  });

  testWidgets('fullscreen reveals controls and center double tap pauses', (
    tester,
  ) async {
    final player = FakeNativePlayer()..isPlaying = true;
    await _mount(tester, player, shortSeries: true);
    await tester.tap(find.byKey(const ValueKey('player-fullscreen-pill')));
    await tester.pump();
    await tester.binding.setSurfaceSize(const Size(800, 450));
    await tester.pump();
    expect(find.byKey(const ValueKey('player-clear-screen')), findsNothing);
    expect(find.text('恢复'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.tapAt(const Offset(400, 200));
    await tester.pump(const Duration(milliseconds: 350));
    expect(player.isPlaying, isTrue);
    expect(find.byKey(const ValueKey('landscape-play')), findsOneWidget);
    await _doubleTap(tester, const Offset(400, 200));
    expect(player.isPlaying, isFalse);
    await _doubleTap(tester, const Offset(400, 200));
    expect(player.isPlaying, isTrue);
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('player-fullscreen-pill')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clear screen and restore stay reachable on a narrow screen with large text',
    (tester) async {
      final player = FakeNativePlayer()..isPlaying = true;
      await _mount(tester, player, textScale: 2.5, shortSeries: true);
      await tester.binding.setSurfaceSize(const Size(280, 600));
      await tester.pump(const Duration(seconds: 4));
      final clearAction = find.byKey(const ValueKey('player-clear-screen'));
      final rateAction = find.byKey(const ValueKey('player-rate-text'));
      expect(clearAction.hitTestable(), findsOneWidget);
      expect(rateAction, findsNothing);
      final iconRect = tester.getRect(clearAction);
      expect(iconRect.left, greaterThanOrEqualTo(0));
      expect(iconRect.right, lessThanOrEqualTo(280));
      expect(iconRect.height, greaterThanOrEqualTo(48));
      await tester.tap(clearAction);
      await tester.pump();
      _expectClearScreen();
      expect(rateAction.hitTestable(), findsOneWidget);
      for (final action in [clearAction, rateAction]) {
        final rect = tester.getRect(action);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(280));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      await tester.tap(find.text('恢复'));
      await tester.pump();
      expect(find.byKey(const ValueKey('player-clear-icon')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('portrait swipes keep paging and never adjust the device', (
    tester,
  ) async {
    final selected = <int>[];
    await _mount(
      tester,
      FakeNativePlayer()..isPlaying = true,
      selected: selected,
    );
    await tester.dragFrom(const Offset(160, 400), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(selected, contains(1));
    expect(nativeCalls, isEmpty);
  });

  testWidgets(
    'landscape vertical swipes adjust brightness and volume without paging',
    (tester) async {
      final player = FakeNativePlayer()..isPlaying = true;
      final selected = <int>[];
      await _mount(tester, player, landscape: true, selected: selected);
      final video = tester.element(find.byKey(const ValueKey('video-frame')));
      player.calls.clear();
      await _slide(tester, const Offset(200, 200), const Offset(0, -50));
      await _slide(tester, const Offset(600, 200), const Offset(0, 60));
      expect(nativeCalls, isEmpty);
      expect(
        displayCalls.map((call) => call.method),
        containsAllInOrder(['beginPlayerBrightness', 'setPlayerBrightness']),
      );
      expect(player.volume, lessThan(1));
      expect(find.textContaining('音量'), findsOneWidget);
      expect(
        tester.element(find.byKey(const ValueKey('video-frame'))),
        same(video),
      );
      expect(player.calls.every((call) => call.startsWith('volume:')), isTrue);
      expect(player.isPlaying, isTrue);
      expect(selected, isEmpty);
    },
  );

  testWidgets('landscape double taps seek at sides and pause at center', (
    tester,
  ) async {
    final player = FakeNativePlayer()..isPlaying = true;
    player.currentPosition = const Duration(seconds: 30);
    await _mount(tester, player, landscape: true);
    player.calls.clear();
    Future<void> doubleTap(Offset point) async {
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 350));
    }

    await doubleTap(const Offset(100, 200));
    expect(player.calls, contains('seek:20'));
    await doubleTap(const Offset(700, 200));
    expect(player.calls, contains('seek:30'));
    await doubleTap(const Offset(400, 200));
    expect(player.calls, contains('pause'));
  });

  testWidgets('landscape hold restores saved speed after release and cancel', (
    tester,
  ) async {
    final player = FakeNativePlayer()..isPlaying = true;
    await _mount(tester, player, landscape: true);
    final hold = await tester.startGesture(const Offset(400, 200));
    await tester.pump(const Duration(milliseconds: 600));
    expect(player.rate, 2);
    await hold.up();
    await tester.pump();
    expect(player.rate, 1.5);
    final cancelled = await tester.startGesture(const Offset(400, 200));
    await tester.pump(const Duration(milliseconds: 600));
    expect(player.rate, 2);
    await cancelled.cancel();
    await tester.pump();
    expect(player.rate, 1.5);
  });

  testWidgets(
    'landscape seek previews until release and cancel does not seek',
    (tester) async {
      final player = FakeNativePlayer()..isPlaying = true;
      await _mount(tester, player, landscape: true);
      player.calls.clear();
      final drag = await tester.startGesture(const Offset(200, 200));
      await drag.moveBy(const Offset(160, 0));
      await tester.pump();
      expect(player.calls.where((call) => call.startsWith('seek:')), isEmpty);
      expect(
        find.byKey(const ValueKey('player-gesture-feedback')),
        findsOneWidget,
      );
      await drag.up();
      await tester.pump();
      expect(
        player.calls.where((call) => call.startsWith('seek:')),
        hasLength(1),
      );
      player.calls.clear();
      final cancelled = await tester.startGesture(const Offset(200, 200));
      await cancelled.moveBy(const Offset(160, 0));
      await tester.pump();
      await cancelled.cancel();
      await tester.pump(const Duration(milliseconds: 350));
      expect(player.calls.where((call) => call.startsWith('seek:')), isEmpty);
    },
  );

  testWidgets('short-series landscape double taps clamp to the timeline', (
    tester,
  ) async {
    final player = FakeNativePlayer()..isPlaying = true;
    player.currentPosition = const Duration(seconds: 5);
    await _mount(tester, player, landscape: true, shortSeries: true);
    await _doubleTap(tester, const Offset(100, 200));
    expect(player.position, Duration.zero);
    player.currentPosition = const Duration(seconds: 118);
    player.positions.add(player.currentPosition);
    await _doubleTap(tester, const Offset(700, 200));
    expect(player.position, player.duration);
    expect(player.isPlaying, isTrue);
  });

  testWidgets('pending seek cannot clear a newer relative preview', (
    tester,
  ) async {
    final player = _DelayedSeekPlayer()..isPlaying = true;
    await _mount(tester, player, landscape: true);
    final first = await tester.startGesture(const Offset(200, 200));
    await first.moveBy(const Offset(160, 0));
    await tester.pump();
    await first.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(player.targets, [const Duration(seconds: 44)]);

    final second = await tester.startGesture(const Offset(200, 200));
    await second.moveBy(const Offset(160, 0));
    await tester.pump();
    player.gates.first.complete();
    await tester.pump();
    expect(find.text('01:08 / 02:00'), findsOneWidget);
    await second.up();
    await tester.pump();
    expect(player.targets.last, const Duration(seconds: 68));
    player.gates.last.complete();
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('double tap continues from a pending drag target', (
    tester,
  ) async {
    final player = _DelayedSeekPlayer()..isPlaying = true;
    await _mount(tester, player, landscape: true);
    final drag = await tester.startGesture(const Offset(200, 200));
    await drag.moveBy(const Offset(160, 0));
    await tester.pump();
    await drag.up();
    await tester.pump(const Duration(milliseconds: 100));
    await _doubleTap(tester, const Offset(700, 200));
    expect(player.targets, [
      const Duration(seconds: 44),
      const Duration(seconds: 54),
    ]);
    player.gates.first.complete();
    await tester.pump();
    expect(find.textContaining('快进 10秒'), findsOneWidget);
    player.gates.last.complete();
    await tester.pump(const Duration(milliseconds: 350));
  });

  for (final cancel in [false, true]) {
    testWidgets('late brightness start is released (cancel=$cancel)', (
      tester,
    ) async {
      final pending = Completer<double>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('fqapp/display'),
        (call) async {
          displayCalls.add(call);
          if (call.method == 'beginPlayerBrightness') return pending.future;
          return call.method == 'setPlayerBrightness' ? true : null;
        },
      );
      final player = FakeNativePlayer()..isPlaying = true;
      await _mount(tester, player, landscape: true);
      final drag = await tester.startGesture(const Offset(200, 200));
      await drag.moveBy(const Offset(0, -60));
      await tester.pump();
      if (cancel) {
        await drag.cancel();
      } else {
        await drag.up();
      }
      await tester.pump();
      pending.complete(.5);
      await tester.pump(const Duration(milliseconds: 350));
      expect(displayCalls.map((call) => call.method), [
        'beginPlayerBrightness',
        'endPlayerBrightness',
      ]);
      expect(
        find.byKey(const ValueKey('player-gesture-feedback')),
        findsNothing,
      );
    });
  }

  for (final leave in ['portrait', 'inactive', 'exit']) {
    testWidgets('brightness and boost restore on $leave', (tester) async {
      final player = FakeNativePlayer()..isPlaying = true;
      await _mount(tester, player, landscape: true);
      await _slide(tester, const Offset(200, 200), const Offset(0, -60));
      expect(
        displayCalls.map((call) => call.method),
        contains('setPlayerBrightness'),
      );
      final hold = await tester.startGesture(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 600));
      expect(player.rate, 2);
      if (leave == 'portrait') {
        await tester.binding.setSurfaceSize(const Size(400, 800));
      } else if (leave == 'inactive') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pump();
      expect(player.rate, 1.5);
      expect(displayCalls.last.method, 'endPlayerBrightness');
      await hold.cancel();
      await tester.pump(const Duration(milliseconds: 350));
    });
  }

  testWidgets('volume drag clamps and a paused video remains paused', (
    tester,
  ) async {
    final player = FakeNativePlayer()..volume = .5;
    await _mount(tester, player, landscape: true);
    await _slide(tester, const Offset(600, 200), const Offset(0, 600));
    expect(player.volume, 0);
    await _slide(tester, const Offset(600, 200), const Offset(0, -600));
    expect(player.volume, 1);
    expect(player.isPlaying, isFalse);
    expect(displayCalls, isEmpty);
  });

  testWidgets('adjusted brightness survives taps seeks and holds until exit', (
    tester,
  ) async {
    var brightness = .5;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('fqapp/display'),
      (call) async {
        displayCalls.add(call);
        if (call.method == 'beginPlayerBrightness') return brightness;
        if (call.method == 'setPlayerBrightness') {
          brightness = (call.arguments as Map)['brightness'] as double;
          return true;
        }
        if (call.method == 'endPlayerBrightness') brightness = .5;
        return null;
      },
    );
    final player = FakeNativePlayer()..isPlaying = true;
    await _mount(tester, player, landscape: true);
    await _slide(tester, const Offset(200, 200), const Offset(0, -60));
    final adjusted = brightness;
    expect(adjusted, greaterThan(.5));

    await tester.tapAt(const Offset(400, 200));
    await tester.pump(const Duration(milliseconds: 350));
    expect(player.isPlaying, isTrue);
    expect(brightness, adjusted);
    await tester.tapAt(const Offset(400, 200));
    await tester.pump(const Duration(milliseconds: 350));
    expect(player.isPlaying, isTrue);
    final drag = await tester.startGesture(const Offset(200, 200));
    await drag.moveBy(const Offset(160, 0));
    await tester.pump();
    await drag.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(brightness, adjusted);
    final hold = await tester.startGesture(const Offset(400, 200));
    await tester.pump(const Duration(milliseconds: 600));
    expect(player.rate, 2);
    expect(brightness, adjusted);
    await hold.cancel();
    await tester.pump(const Duration(milliseconds: 350));
    expect(brightness, adjusted);
    expect(
      displayCalls.where((call) => call.method == 'endPlayerBrightness'),
      isEmpty,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(brightness, .5);
    expect(
      displayCalls.where((call) => call.method == 'endPlayerBrightness'),
      hasLength(1),
    );
  });

  testWidgets('cancelling an active brightness drag restores its lease once', (
    tester,
  ) async {
    final player = FakeNativePlayer()..isPlaying = true;
    await _mount(tester, player, landscape: true);
    final drag = await tester.startGesture(const Offset(200, 200));
    await drag.moveBy(const Offset(0, -60));
    await tester.pump();
    expect(
      displayCalls.map((call) => call.method),
      contains('setPlayerBrightness'),
    );
    await drag.cancel();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      displayCalls.where((call) => call.method == 'endPlayerBrightness'),
      hasLength(1),
    );
  });

  testWidgets('gesture HUD fits a small landscape with large text', (
    tester,
  ) async {
    await _mount(
      tester,
      FakeNativePlayer()..isPlaying = true,
      landscape: true,
      textScale: 2.5,
    );
    await tester.binding.setSurfaceSize(const Size(480, 280));
    await tester.pump();
    final drag = await tester.startGesture(const Offset(100, 140));
    await drag.moveBy(const Offset(160, 0));
    await tester.pump();
    final feedback = find.byKey(const ValueKey('player-gesture-feedback'));
    expect(feedback, findsOneWidget);
    final rect = tester.getRect(feedback);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(480));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(280));
    expect(tester.takeException(), isNull);
    await drag.cancel();
    await tester.pump(const Duration(milliseconds: 350));
    final brightness = await tester.startGesture(const Offset(100, 140));
    await brightness.moveBy(const Offset(0, -35));
    await tester.pump();
    await brightness.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(find.byKey(const ValueKey('player-gesture-label')), findsOneWidget);
    final hud = tester.getRect(
      find.byKey(const ValueKey('player-gesture-hud')),
    );
    expect(hud.left, greaterThanOrEqualTo(0));
    expect(hud.right, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
    await brightness.up();
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('fullscreen controls fit and auto-hide even with large fonts', (
    tester,
  ) async {
    await _mount(
      tester,
      FakeNativePlayer()..isPlaying = true,
      landscape: true,
      textScale: 2.5,
    );
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('更多'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('更多'), findsNothing);
    expect(find.byKey(const ValueKey('landscape-seek')), findsNothing);
    expect(find.text('恢复'), findsNothing);
  });
}

void _expectClearScreen() {
  expect(find.byTooltip('返回'), findsNothing);
  expect(find.byKey(const ValueKey('video-controls')), findsNothing);
  expect(find.byKey(const ValueKey('player-catalog-bar')), findsNothing);
  expect(find.byKey(const ValueKey('player-follow-button')), findsNothing);
  expect(find.byKey(const ValueKey('player-fullscreen-pill')), findsNothing);
  expect(find.byKey(const ValueKey('video-seek')), findsNothing);
  expect(find.byKey(const ValueKey('landscape-seek')), findsNothing);
  expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  expect(
    find.byKey(const ValueKey('player-rate-text')).hitTestable(),
    findsOneWidget,
  );
  expect(find.text('恢复').hitTestable(), findsOneWidget);
}

Future<void> _slide(WidgetTester tester, Offset start, Offset delta) async {
  final gesture = await tester.startGesture(start);
  await gesture.moveBy(Offset(0, delta.dy.sign * 25));
  await tester.pump();
  await gesture.moveBy(delta);
  await tester.pump();
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _doubleTap(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _mount(
  WidgetTester tester,
  FakeNativePlayer player, {
  bool landscape = false,
  List<int>? selected,
  double textScale = 1,
  bool shortSeries = false,
}) async {
  await tester.binding.setSurfaceSize(
    landscape ? const Size(800, 450) : const Size(400, 800),
  );
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Double-tap recognizers leave a short minimum-tap timer after a drag.
    await tester.pump(const Duration(milliseconds: 350));
    await player.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    _app(
      player,
      selected: selected,
      textScale: textScale,
      shortSeries: shortSeries,
    ),
  );
  await tester.pumpAndSettle();
  if (landscape) {
    if (shortSeries) {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('player-fullscreen-pill')));
      await tester.binding.setSurfaceSize(const Size(800, 450));
    } else {
      await tester.tap(find.byTooltip('全屏'));
    }
    await tester.pumpAndSettle();
  }
}

Widget _app(
  FakeNativePlayer player, {
  List<int>? selected,
  int index = 0,
  double textScale = 1,
  bool shortSeries = false,
  bool enabled = true,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: StreamBuilder<bool>(
    stream: player.playingStream,
    initialData: player.playing,
    builder: (context, playing) => VideoPlayerChrome(
      player: player,
      title: '交互测试短剧',
      episodes: List.generate(
        3,
        (i) => Chapter(itemId: '$i', title: '第 ${i + 1} 集', volumeName: ''),
      ),
      currentIndex: index,
      duration: player.duration,
      playing: playing.data!,
      shortSeries: shortSeries,
      enabled: enabled,
      onSelectEpisode: (value) async {
        selected?.add(value);
      },
      onError: (error) => throw error,
      child: const ColoredBox(color: Colors.black),
    ),
  ),
);

class _DelayedSeekPlayer extends FakeNativePlayer {
  final targets = <Duration>[];
  final gates = <Completer<void>>[];

  @override
  Future<void> seek(Duration position) async {
    targets.add(position);
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    await super.seek(position);
  }
}
