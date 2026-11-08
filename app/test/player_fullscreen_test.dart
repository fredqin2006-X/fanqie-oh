import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/models/playlet_comment.dart';
import 'package:fqapp/widgets/video_player_chrome.dart';
import 'support/fakes.dart';

void main() {
  for (final portraitSource in [true, false]) {
    for (final shortSeries in [true, false]) {
      for (final immediate in [true, false]) {
        testWidgets(
          'fullscreen auto-hides and reveals controls (portrait source=$portraitSource, short=$shortSeries, immediate=$immediate)',
          (tester) async {
            SharedPreferences.setMockInitialValues({});
            await tester.binding.setSurfaceSize(const Size(400, 800));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final orientations = <List<String>>[];
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              (call) async {
                if (call.method == 'SystemChrome.setPreferredOrientations') {
                  orientations.add(List<String>.from(call.arguments as List));
                }
                return null;
              },
            );
            addTearDown(
              () => tester.binding.defaultBinaryMessenger
                  .setMockMethodCallHandler(SystemChannels.platform, null),
            );
            final player = FakeNativePlayer(
              width: portraitSource ? 720 : 1280,
              height: portraitSource ? 1280 : 720,
            )..isPlaying = true;
            await tester.pumpWidget(
              MaterialApp(
                home: VideoPlayerChrome(
                  player: player,
                  shortSeries: shortSeries,
                  startFullscreen: immediate,
                  title: '测试播放标题',
                  episodes: [
                    Chapter(itemId: '1', title: '第一集', volumeName: ''),
                  ],
                  currentIndex: 0,
                  duration: player.duration,
                  playing: true,
                  danmakuEnabled: true,
                  danmaku: const [
                    PlayletComment(id: 'test', text: '保留弹幕', offsetMs: 0),
                  ],
                  onSelectEpisode: (_) async {},
                  onError: (error) => throw error,
                  child: const ColoredBox(
                    key: ValueKey('actual-video'),
                    color: Colors.blue,
                  ),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 100));
            if (!immediate) {
              await tester.tap(
                shortSeries
                    ? find.byKey(const ValueKey('player-fullscreen-pill'))
                    : find.byTooltip('全屏'),
              );
            }
            await tester.binding.setSurfaceSize(const Size(800, 450));
            await tester.pump(const Duration(milliseconds: 100));
            expect(
              orientations.last,
              immediate || !portraitSource
                  ? [
                      'DeviceOrientation.landscapeLeft',
                      'DeviceOrientation.landscapeRight',
                    ]
                  : ['DeviceOrientation.portraitUp'],
            );
            expect(find.byKey(const ValueKey('actual-video')), findsOneWidget);
            await tester.pump(const Duration(seconds: 4));
            expect(find.byType(IconButton), findsNothing);
            expect(find.byKey(const ValueKey('landscape-seek')), findsNothing);
            if (shortSeries) {
              expect(
                find.byKey(const ValueKey('player-danmaku-layer')),
                findsOneWidget,
              );
            }
            await tester.tapAt(const Offset(400, 190));
            await tester.pump(const Duration(milliseconds: 400));
            expect(player.isPlaying, isTrue);
            expect(find.byTooltip('返回'), findsOneWidget);
            expect(
              find.byKey(
                ValueKey(shortSeries ? 'landscape-seek' : 'video-seek'),
              ),
              findsOneWidget,
            );
            await tester.binding.handlePopRoute();
            await tester.pump(const Duration(milliseconds: 100));
            expect(find.byType(VideoPlayerChrome), findsOneWidget);
            expect(orientations.last, ['DeviceOrientation.portraitUp']);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            expect(orientations.last, isEmpty);
            await player.dispose();
          },
        );
      }
    }
  }
}
