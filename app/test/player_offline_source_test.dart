import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/models/playlet_comment.dart';
import 'package:fqapp/pages/player_page.dart';
import 'package:fqapp/services/drama_cache_preferences.dart';
import 'package:fqapp/services/drama_download_store.dart';

import 'support/controlled_player.dart';
import 'support/fakes.dart';

const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _native = MethodChannel('fqapp/native_player');

void main() {
  late Directory directory;
  late File file;
  late MemoryDramaDownloadStore store;
  late List<ControlledNativePlayer> players;
  late List<String> requests;
  late bool online;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DramaCachePreferences.instance.resetForTest();
    directory = Directory.systemTemp.createTempSync('fqapp-offline-video-');
    file = File('${directory.path}/episode #1%.mp4')
      ..writeAsBytesSync(List.filled(16, 1));
    store = MemoryDramaDownloadStore(videoDirectory: directory);
    await store.saveEpisode(
      CachedEpisode(
        seriesId: 'offline-series',
        itemId: '1',
        title: '第 1 集',
        index: 0,
        keyHex: '',
        height: 720,
        variantName: '720P',
        bytes: 16,
        filePath: file.path,
        cachedAt: 1,
      ),
    );
    players = [];
    requests = [];
    online = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_native, (_) async => null);
    messenger.setMockMethodCallHandler(
      _connectivity,
      (_) async => [online ? 'wifi' : 'none'],
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_native, null);
    messenger.setMockMethodCallHandler(_connectivity, null);
    DramaCachePreferences.instance.resetForTest();
    directory.deleteSync(recursive: true);
  });

  Future<void> mount(WidgetTester tester, {int episodeCount = 1}) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await flush(tester);
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          bookId: 'offline-series',
          title: '缓存播放测试',
          eps: [
            for (var index = 1; index <= episodeCount; index++)
              Chapter(itemId: '$index', title: '第 $index 集', volumeName: ''),
          ],
          startIndex: 0,
          shortSeries: true,
          historyStore: MemoryReaderStore(),
          danmakuFetcher: (_) async => const PlayletCommentPage(),
          store: store,
          contentLoader: (chapter) async {
            requests.add(chapter.itemId);
            return {
              'video_url': 'https://example.invalid/${chapter.itemId}.mp4',
            };
          },
          playerFactory: () {
            final player = ControlledNativePlayer(hasFirstFrame: false);
            players.add(player);
            return player;
          },
        ),
      ),
    );
    await flush(tester);
  }

  testWidgets('完整缓存离线优先，特殊字符路径能还原且不请求在线源', (tester) async {
    online = false;
    await mount(tester);
    expect(players.single.calls.first, 'create:${Uri.file(file.path)}');
    expect(requests, isEmpty);
    expect(players.single.isPlaying, isTrue);
  });

  for (final corruption in ['missing', 'empty', 'truncated', 'oversized']) {
    testWidgets('$corruption 缓存不交给播放器，改取在线源', (tester) async {
      if (corruption == 'missing') {
        file.deleteSync();
      } else {
        file.writeAsBytesSync(
          List.filled(
            corruption == 'empty' ? 0 : (corruption == 'truncated' ? 8 : 32),
            1,
          ),
        );
      }
      await mount(tester);
      expect(
        players.single.calls.first,
        'create:https://example.invalid/1.mp4',
      );
      expect(requests, ['1']);
      expect(await store.episode('1'), isNotNull, reason: '回退不删除用户缓存记录');
    });
  }

  testWidgets('本地起播失败后静默重试在线源，不会反复命中同一缓存', (tester) async {
    await mount(tester);
    final local = players.single;
    local.errors.add(StateError('cached media cannot be decoded'));
    await flush(tester);
    await flush(tester);
    expect(players, hasLength(2));
    expect(local.disposed, isTrue);
    expect(players.last.calls.first, 'create:https://example.invalid/1.mp4');
    expect(requests, ['1']);
    expect(file.lengthSync(), 16);
    expect(await store.episode('1'), isNotNull);
  });

  testWidgets('已出画面的本地源失败后，手动重试在线源并保持续播位置', (tester) async {
    await mount(tester);
    players.single.emitFirstFrame();
    await flush(tester);
    players.single.emitPosition(const Duration(seconds: 13));
    players.single.errors.add(StateError('cached media read failed'));
    await flush(tester);
    expect(players, hasLength(1));
    await tester.tap(find.text('重试'));
    await tester.pump(const Duration(milliseconds: 350));
    await flush(tester);
    await flush(tester);
    expect(players.last.calls.first, 'create:https://example.invalid/1.mp4');
    expect(players.last.position, const Duration(seconds: 13));
    expect(requests, ['1']);
  });

  testWidgets('下一集本地预热失败后，切集重新取在线源', (tester) async {
    final second = File('${directory.path}/episode2.mp4')
      ..writeAsBytesSync(List.filled(16, 1));
    await tester.runAsync(() => store.removeEpisode('1'));
    await store.saveEpisode(
      CachedEpisode(
        seriesId: 'offline-series',
        itemId: '2',
        title: '第 2 集',
        index: 1,
        keyHex: '',
        height: 720,
        variantName: '720P',
        bytes: 16,
        filePath: second.path,
        cachedAt: 1,
      ),
    );
    await mount(tester, episodeCount: 2);
    final first = players.single;
    first.emitFirstFrame();
    first.emitDuration(const Duration(minutes: 2));
    first.emitPosition(const Duration(seconds: 100));
    await tester.pump(const Duration(seconds: 5));
    await flush(tester);
    expect(players, hasLength(2));
    final warm = players.last;
    expect(warm.calls.first, 'create:${Uri.file(second.path)}');
    warm.errors.add(StateError('offline warmup failed'));
    await flush(tester);
    expect(warm.disposed, isTrue);
    first.emitCompleted();
    await flush(tester);
    await flush(tester);
    expect(players, hasLength(3));
    expect(players.last.calls.first, 'create:https://example.invalid/2.mp4');
    expect(second.existsSync(), isTrue);
  });

  testWidgets('断网时本地起播失败仍重试缓存，不发起在线请求或删除缓存', (tester) async {
    online = false;
    await mount(tester);
    for (var attempt = 0; attempt < 3; attempt++) {
      players.last.errors.add(StateError('local decoder failed'));
      await flush(tester);
    }
    expect(players, hasLength(3));
    expect(
      players.every((player) => player.calls.first.startsWith('create:file:')),
      isTrue,
    );
    expect(requests, isEmpty);
    expect(file.existsSync(), isTrue);
    expect(find.text('播放失败'), findsOneWidget);
  });
}

Future<void> flush(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}
