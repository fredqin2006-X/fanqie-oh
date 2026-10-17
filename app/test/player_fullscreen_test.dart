import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/models/playlet_comment.dart';
import 'package:fqapp/widgets/video_player_chrome.dart';
import 'support/fakes.dart';

void main() {
  for (final portrait in [true, false]) {
    for (final shortSeries in [true, false]) {
      for (final startFullscreen in [true, false]) {
      testWidgets('fullscreen hides UI and locks ${portrait ? 'portrait' : 'landscape'} (short=$shortSeries, immediate=$startFullscreen)', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final orientations = <List<String>>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientations.add(List<String>.from(call.arguments as List));
          }
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
        final player = FakeNativePlayer(width: portrait ? 720 : 1280, height: portrait ? 1280 : 720)..isPlaying = true;
        await tester.pumpWidget(MaterialApp(home: VideoPlayerChrome(
          player: player, shortSeries: shortSeries, startFullscreen: startFullscreen, title: '不应在全屏显示的标题',
          episodes: [Chapter(itemId: '1', title: '第一集', volumeName: '')],
          currentIndex: 0, duration: player.duration, playing: true,
          danmakuEnabled: true,
          danmaku: const [PlayletComment(id: 'test', text: '保留弹幕', offsetMs: 0)],
          onSelectEpisode: (_) async {}, onError: (error) => throw error,
          child: const ColoredBox(key: ValueKey('actual-video'), color: Colors.blue),
        )));
        await tester.pump(const Duration(milliseconds: 100));
        if (!startFullscreen) await tester.tap(shortSeries ? find.byKey(const ValueKey('player-fullscreen-pill')) : find.byTooltip('全屏'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(orientations.last, [portrait ? 'DeviceOrientation.portraitUp' : 'DeviceOrientation.landscapeLeft']);
        expect(find.byKey(const ValueKey('actual-video')), findsOneWidget);
        expect(find.text('不应在全屏显示的标题'), findsNothing);
        expect(find.byType(IconButton), findsNothing);
        expect(find.byKey(const ValueKey('video-seek')), findsNothing);
        expect(find.byKey(const ValueKey('landscape-seek')), findsNothing);
        expect(find.byKey(const ValueKey('landscape-lock')), findsNothing);
        expect(find.text('恢复'), findsNothing);
        if (shortSeries) expect(find.byKey(const ValueKey('player-danmaku-layer')), findsOneWidget);
        // Touching the video cannot reveal controls; system back exits fullscreen.
        await tester.tap(find.byKey(const ValueKey('video-surface')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(IconButton), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(VideoPlayerChrome), findsOneWidget);
        expect(orientations.last, isEmpty);
        expect(shortSeries ? find.byKey(const ValueKey('player-fullscreen-pill')) : find.byTooltip('全屏'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await player.dispose();
      });
      }
    }
  }
}
