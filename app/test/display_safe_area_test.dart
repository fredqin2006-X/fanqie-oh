import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/platform/display_safe_area.dart';

const _events = MethodChannel('fqapp/display/events');
const _codec = StandardMethodCodec();

void main() {
  late DisplaySafeAreaController controller;
  late Map<String, num> cutout;
  setUp(() {
    controller = DisplaySafeAreaController();
    cutout = {'top': 120, 'left': 0, 'right': 0, 'bottom': 0};
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_events, (_) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('fqapp/display'), (_) async => cutout);
  });
  tearDown(() {
    controller.dispose();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_events, null);
    messenger.setMockMethodCallHandler(const MethodChannel('fqapp/display'), null);
  });

  Future<void> mount(WidgetTester tester, {bool featureOnly = false}) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [controller],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero,
          displayFeatures: featureOnly ? const [ui.DisplayFeature(
            bounds: Rect.fromLTWH(180, 12, 40, 24),
            type: ui.DisplayFeatureType.cutout, state: ui.DisplayFeatureState.unknown,
          )] : const [],
        ),
        child: DisplaySafeArea(enabled: true, controller: controller, child: child!),
      ),
      home: const DisplaySafeBackground(color: Colors.black,
        child: Scaffold(backgroundColor: Colors.black,
          body: SafeArea(child: SizedBox.expand(key: ValueKey('safe-content'))))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('reserves the cutout once, including a floating punch-hole gap', (tester) async {
    await mount(tester);
    expect(tester.getTopLeft(find.byKey(const ValueKey('safe-content'))).dy, 60);
    final context = tester.element(find.byKey(const ValueKey('safe-content')));
    expect(MediaQuery.paddingOf(context), EdgeInsets.zero);
    expect(MediaQuery.sizeOf(context), const Size(400, 740));
    expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('display-safe-background'))).color, Colors.black);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rotation moves the reserved band to the cutout side', (tester) async {
    await mount(tester);
    tester.view.physicalSize = const Size(1600, 800);
    cutout = {'top': 0, 'left': 120, 'right': 0, 'bottom': 0};
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(_events.name, _codec.encodeSuccessEnvelope(cutout), (_) {});
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('safe-content'))), const Offset(60, 0));
    expect(tester.getSize(find.byKey(const ValueKey('safe-content'))), const Size(740, 400));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Flutter cutout features protect the window before native metrics arrive', (tester) async {
    cutout = {};
    await mount(tester, featureOnly: true);
    expect(tester.getTopLeft(find.byKey(const ValueKey('safe-content'))).dy, 36);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pushed pages use their own background and restore it on back', (tester) async {
    await mount(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const DisplaySafeBackground(
      color: Color(0xFFF5E6C8), child: Scaffold(body: Text('阅读背景')))));
    await tester.pumpAndSettle();
    expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('display-safe-background'))).color, const Color(0xFFF5E6C8));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('display-safe-background'))).color, Colors.black);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
