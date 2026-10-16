import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/services/audio_preferences.dart';
import 'package:fqapp/services/chapter_text_formatter.dart';
import 'package:fqapp/services/listening_session.dart';
import 'package:fqapp/services/system_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _methods = MethodChannel('fqapp/system_tts');
const _eventMethods = MethodChannel('fqapp/system_tts_events');
const _playerMethods = MethodChannel('fqapp/native_player');
const _codec = StandardMethodCodec();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  Completer<int>? initialization;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AudioPreferences.instance.resetForTest();
    ListeningSession.instance.clear();
    calls = [];
    initialization = null;
    messenger.setMockMethodCallHandler(_eventMethods, (_) async => null);
    messenger.setMockMethodCallHandler(_playerMethods, (_) async => null);
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      if (call.method == 'initialize') return initialization?.future ?? 4000;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_eventMethods, null);
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockMethodCallHandler(_playerMethods, null);
  });

  List<MethodCall> spoken() => calls.where((c) => c.method == 'speak').toList();
  Future<void> event(Map<String, Object?> data) =>
      messenger.handlePlatformMessage(
        _eventMethods.name,
        _codec.encodeSuccessEnvelope(data),
        (_) {},
      );

  SystemTtsPlayback session({
    String text = '正文。',
    Future<String> Function(Chapter)? loader,
  }) => SystemTtsPlayback(
    SystemTtsBook(
      bookId: 'local:book',
      title: '本地书',
      chapters: [
        Chapter(itemId: 'c1', title: '第一章', volumeName: '正文'),
        Chapter(itemId: 'c2', title: '第二章', volumeName: '正文'),
      ],
      startIndex: 0,
      localOnly: true,
      initialContent: ChapterContent.fromPlainText(text),
      textLoader: loader,
    ),
    beforePlay: () async {},
    onStop: () {},
  );

  testWidgets('pause invalidates a pending engine initialization', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    initialization = Completer<int>();
    final playback = session();
    try {
      playback.start();
      await tester.pump();
      expect(calls.any((c) => c.method == 'initialize'), isTrue);
      await playback.pause();
      initialization!.complete(4000);
      await tester.pump();
      expect(spoken(), isEmpty);
      expect(playback.wantPlay, isFalse);
    } finally {
      if (!initialization!.isCompleted) initialization!.complete(4000);
      await playback.close();
      await tester.pump();
    }
  });

  testWidgets(
    'closing during next local chapter load rejects its late result',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final chapter = Completer<String>();
      final requested = <String>[];
      final playback = session(
        loader: (c) {
          requested.add(c.itemId);
          return chapter.future;
        },
      );
      try {
        playback.start();
        await tester.pump();
        final id = (spoken().single.arguments as Map)['id'];
        await event({'type': 'done', 'id': id});
        await tester.pump();
        expect(requested, ['c2']);
        await playback.close();
        chapter.complete('迟到的第二章');
        await tester.pump();
        expect(spoken(), hasLength(1));
        expect(ListeningSession.instance.bookId, isNull);
      } finally {
        if (!chapter.isCompleted) chapter.complete('第二章');
        await playback.close();
        await tester.pump();
      }
    },
  );

  testWidgets(
    'resume uses the reported range and ignores an old done callback',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final playback = session(text: '甲乙丙丁。');
      try {
        playback.start();
        await tester.pump();
        final oldId = (spoken().single.arguments as Map)['id'];
        await event({'type': 'range', 'id': oldId, 'start': 2});
        await playback.pause();
        await playback.resume();
        expect((spoken().last.arguments as Map)['text'], '丙丁。');
        await event({'type': 'done', 'id': oldId});
        await tester.pump();
        expect(playback.index, 0);
        expect(spoken(), hasLength(2));
        expect(ListeningSession.instance.duration, Duration.zero);
        expect(ListeningSession.instance.textProgress, closeTo(0.4, 0.001));
      } finally {
        await playback.close();
        await tester.pump();
      }
    },
  );

  testWidgets(
    'chunk boundaries preserve an astral character and chapter text',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final text = '${List.filled(299, '甲').join()}😀乙';
      final playback = session(text: text);
      try {
        playback.start();
        await tester.pump();
        final first = spoken().single.arguments as Map;
        expect((first['text'] as String).length, 299);
        await event({'type': 'done', 'id': first['id']});
        await tester.pump();
        final second = spoken().last.arguments as Map;
        expect(second['text'], '😀乙');
        expect('${first['text']}${second['text']}', text);
      } finally {
        await playback.close();
        await tester.pump();
      }
    },
  );

  testWidgets(
    'background disabled and engine interruptions cancel pending play',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final playback = session();
      try {
        playback.start();
        await tester.pump();
        await AudioPreferences.instance.setBackgroundPlayback(false);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(playback.wantPlay, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await playback.resume();
        await event({'type': 'interrupted', 'id': null});
        await tester.pump();
        expect(playback.wantPlay, isFalse);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await playback.close();
        await tester.pump();
      }
    },
  );

  test(
    'local books without a loader fail instead of falling back to an API',
    () async {
      final playback = session();
      await expectLater(playback.book.load(1), throwsStateError);
      playback.dispose();
    },
  );
}
