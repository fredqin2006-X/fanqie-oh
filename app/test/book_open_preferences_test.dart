import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fqapp/services/book_open_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookOpenPreferences.instance.resetForTest();
  });

  test('direct reader defaults to off (detail page first)', () async {
    await BookOpenPreferences.instance.load();
    expect(BookOpenPreferences.instance.directReader.value, isFalse);
  });

  test('direct reader persists across loads', () async {
    await BookOpenPreferences.instance.set(true);
    expect(BookOpenPreferences.instance.directReader.value, isTrue);

    BookOpenPreferences.instance.resetForTest();
    await BookOpenPreferences.instance.load();
    expect(BookOpenPreferences.instance.directReader.value, isTrue);
  });

  test('a wrong-typed stored value falls back to off', () async {
    SharedPreferences.setMockInitialValues({
      'book_open_direct_reader': 'yes',
    });
    await BookOpenPreferences.instance.load();
    expect(BookOpenPreferences.instance.directReader.value, isFalse);
  });
}
