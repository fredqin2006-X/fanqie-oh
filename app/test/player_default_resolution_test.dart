import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/pages/player_page.dart';
import 'package:fqapp/pages/settings_page.dart';
import 'package:fqapp/services/episode_source_cache.dart';
import 'package:fqapp/services/inline_video_playback.dart';
import 'package:fqapp/services/player_preferences.dart';

import 'support/fakes.dart';

Map<String, dynamic> _response() => {
  'video_url': 'https://example.invalid/360.mp4',
  'key_hex': 'low',
  // Deliberately unsorted, with portrait pixel heights, and the main URL low.
  'variants': [
    for (final resolution in [360, 1080, 720])
      {
        'name': '${resolution}P',
        'height': resolution * 16 ~/ 9,
        'url': 'https://example.invalid/$resolution.mp4',
        'key_hex': 'key-$resolution',
      },
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'missing or invalid saved resolution means highest; valid choice persists',
    () async {
      expect(await PlayerPreferences.loadDefaultResolution(), 0);
      await PlayerPreferences.saveDefaultResolution(720);
      expect(await PlayerPreferences.loadDefaultResolution(), 720);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('player_default_resolution', 'bad');
      expect(await PlayerPreferences.loadDefaultResolution(), 0);
    },
  );

  test(
    'matches quality labels, falls back to highest and honors a manual choice',
    () {
      final source = EpisodeSource.fromResponse(_response());
      expect(source.withPreferredResolution(720).keyHex, 'key-720');
      expect(source.withPreferredResolution(540).keyHex, 'key-1080');
      expect(source.withPreferredResolution(0).keyHex, 'key-1080');
      expect(
        source
            .withPreferredResolution(1080, chosen: source.variants.first)
            .keyHex,
        'key-360',
      );
      const single = EpisodeSource('https://example.invalid/only.mp4', 'only');
      expect(identical(single.withPreferredResolution(720), single), isTrue);
    },
  );

  testWidgets(
    'settings exposes and persists default resolution across reopening',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      await tester.tap(find.text('短剧'));
      await tester.pumpAndSettle();
      expect(find.text('最高可用'), findsOneWidget);
      await tester.tap(find.text('默认分辨率'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720P'));
      await tester.pumpAndSettle();
      expect(await PlayerPreferences.loadDefaultResolution(), 720);
      expect(find.text('720P'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('短剧'));
      await tester.pumpAndSettle();
      expect(find.text('720P'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final scenario in [
    (resolution: 720, selected: 720),
    (resolution: 540, selected: 1080),
    (resolution: 0, selected: 1080),
  ]) {
    testWidgets(
      'full player selects ${scenario.selected}P for default ${scenario.resolution}',
      (tester) async {
        await PlayerPreferences.saveDefaultResolution(scenario.resolution);
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('fqapp/native_player'),
          (_) async => null,
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            const MethodChannel('fqapp/native_player'),
            null,
          ),
        );
        final player = FakeNativePlayer();
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerPage(
              bookId: 'series',
              title: '测试短剧',
              shortSeries: true,
              eps: [Chapter(itemId: 'episode', title: '第一集', volumeName: '')],
              startIndex: 0,
              historyStore: MemoryReaderStore(),
              contentLoader: (_) async => _response(),
              playerFactory: () => player,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          player.calls,
          contains('create:https://example.invalid/${scenario.selected}.mp4'),
        );
        expect(player.createdKeys, ['key-${scenario.selected}']);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      },
    );

    test(
      'inline selects ${scenario.selected}P for default ${scenario.resolution}',
      () async {
        await PlayerPreferences.saveDefaultResolution(scenario.resolution);
        final players = <FakeNativePlayer>[];
        final session = InlineVideoPlayback(
          directoryLoader: (_, _) async => [
            [Chapter(itemId: 'episode', title: '第一集', volumeName: '')],
          ],
          contentLoader: (_, _) async => _response(),
          historyStore: MemoryReaderStore(),
          playerFactory: () {
            final player = FakeNativePlayer();
            players.add(player);
            return player;
          },
        );
        addTearDown(session.dispose);
        final series = MediaItem(
          id: 'series',
          title: '测试短剧',
          cover: '',
          author: '',
          badge: '',
          ep: '',
          kind: 'video',
        );
        await session.activate(series);
        expect(
          players.single.calls,
          contains('create:https://example.invalid/${scenario.selected}.mp4'),
        );
        expect(players.single.createdKeys, ['key-${scenario.selected}']);
        // Explicit choice survives recreating this episode, without changing the default.
        await session.switchVariant(session.variants.first);
        await session.disposePlayer();
        await session.activate(series);
        expect(players.last.createdKeys, ['key-360']);
        expect(
          await PlayerPreferences.loadDefaultResolution(),
          scenario.resolution,
        );
      },
    );
  }
}
