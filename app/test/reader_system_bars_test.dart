import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/pages/reader_page.dart';
import 'package:fqapp/widgets/reader/reader_paged_view.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fqapp/reader');
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  List<bool> immersiveRequests() => calls
      .where((call) => call.method == 'setImmersive')
      .map((call) => call.arguments['enabled'] as bool)
      .toList();

  testWidgets('system bars follow reader route and foreground ownership', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Scaffold()),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => _reader()),
    );
    await tester.pumpAndSettle();
    expect(immersiveRequests(), [true]);
    final viewport = tester.getRect(_surface);
    final layout = tester
        .widget<ReaderPagedView>(find.byType(ReaderPagedView))
        .layout;
    for (var i = 0; i < 2; i++) {
      await tester.tapAt(viewport.center);
      await tester.pumpAndSettle();
      expect(tester.getRect(_surface), viewport);
      expect(
        tester.widget<ReaderPagedView>(find.byType(ReaderPagedView)).layout,
        same(layout),
      );
    }
    expect(immersiveRequests(), [true]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(calls.any((call) => call.method == 'suspend'), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(immersiveRequests().last, isTrue);

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(immersiveRequests().last, isFalse);
    calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(immersiveRequests(), isNot(contains(true)));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(immersiveRequests().last, isTrue);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls.any((call) => call.method == 'stop'), isTrue);
    final count = immersiveRequests().length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(immersiveRequests(), hasLength(count));
  });

  testWidgets('empty reader does not hide system navigation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _reader(empty: true)));
    await tester.pumpAndSettle();
    expect(find.text('暂无可阅读章节'), findsOneWidget);
    expect(immersiveRequests(), isNot(contains(true)));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in ['paged', 'scroll']) {
    testWidgets(
      '$mode paints full background but keeps content below a cutout',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'reader_page_mode': mode,
          'reader_show_reading_info': false,
        });
        await tester.binding.setSurfaceSize(const Size(390, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                displayFeatures: const [
                  ui.DisplayFeature(
                    bounds: Rect.fromLTWH(170, 8, 50, 32),
                    type: ui.DisplayFeatureType.cutout,
                    state: ui.DisplayFeatureState.unknown,
                  ),
                ],
              ),
              child: child!,
            ),
            home: _reader(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(Scaffold)),
          const Rect.fromLTWH(0, 0, 390, 800),
        );
        final viewport = tester.getRect(_surface);
        expect(viewport.top, greaterThanOrEqualTo(40));
        await tester.tapAt(viewport.center);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byTooltip('返回书籍')).top,
          greaterThanOrEqualTo(40),
        );
        expect(tester.getRect(_surface), viewport);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final bottom in [24.0, 48.0]) {
    for (final mode in ['paged', 'scroll']) {
      testWidgets('$mode keeps content and controls above a $bottom inset', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          'reader_page_mode': mode,
          'reader_show_reading_info': false,
        });
        await tester.binding.setSurfaceSize(const Size(390, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final padding = EdgeInsets.only(top: 32, bottom: bottom);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: padding, viewPadding: padding),
              child: child!,
            ),
            home: _reader(),
          ),
        );
        await tester.pumpAndSettle();
        final viewport = tester.getRect(_surface);
        expect(viewport.top, greaterThanOrEqualTo(32));
        expect(viewport.bottom, lessThanOrEqualTo(800 - bottom));
        await tester.tapAt(viewport.center);
        await tester.pumpAndSettle();
        final settings = tester.getRect(
          find.byKey(const ValueKey('reader-settings')),
        );
        expect(settings.bottom, lessThanOrEqualTo(800 - bottom));
        expect(tester.getRect(_surface), viewport);
        await tester.tap(find.byTooltip('收起阅读菜单'));
        await tester.pumpAndSettle();
        expect(tester.getRect(_surface), viewport);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

final _surface = find.byKey(const ValueKey('reader-page-surface'));

ReaderPage _reader({bool empty = false}) => ReaderPage(
  bookId: 'system-bars-test',
  title: '安全区测试',
  chapters: empty ? [] : [Chapter(itemId: 'c1', title: '第一章', volumeName: '')],
  startIndex: 0,
  readerStore: MemoryReaderStore(),
  chapterCache: MemoryChapterCache(),
  chapterLoader: (_) async =>
      List.generate(45, (index) => '第 $index 段阅读正文。').join('\n\n'),
);
