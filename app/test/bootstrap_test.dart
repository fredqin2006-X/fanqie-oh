import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/main.dart';
import 'package:fqapp/platform/harmony_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = HarmonyBootstrap.channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'reports native persistence results without exposing keys or paths',
    (tester) async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object>{
          'apiVersion': 26,
          'launchCount': 2,
          'fileReused': true,
          'keyReused': true,
        },
      );
      await tester.pumpWidget(const FqApp());
      await tester.pumpAndSettle();
      expect(find.text('持久启动计数：2'), findsOneWidget);
      expect(find.text('HUKS 解封成功，沿用既有密钥'), findsOneWidget);
    },
  );

  testWidgets('a missing secure/native service blocks success and can retry', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'STORAGE_UNAVAILABLE');
    });
    await tester.pumpWidget(const FqApp());
    await tester.pumpAndSettle();
    expect(find.text('本地数据初始化失败，尚未进入书库。'), findsOneWidget);
    expect(find.text('安全密钥'), findsNothing);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => <String, Object>{
        'apiVersion': 23,
        'launchCount': 1,
        'fileReused': false,
        'keyReused': false,
      },
    );
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('安全密钥'), findsOneWidget);
  });

  test('rejects an unsupported OS or malformed native response', () {
    expect(
      () => BootstrapReport.fromMap({
        'apiVersion': 22,
        'launchCount': 1,
        'fileReused': true,
        'keyReused': true,
      }),
      throwsFormatException,
    );
    expect(
      () => BootstrapReport.fromMap({'apiVersion': 23, 'launchCount': 1}),
      throwsFormatException,
    );
  });
}
