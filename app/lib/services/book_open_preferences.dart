import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「点击书籍直接进入阅读」的持久化开关（issue #19 第 3 条）。
///
/// 默认 false＝点书先进详情页（现有行为）。用户在设置 → 阅读里打开后，
/// 点书架、首页、搜索等处的书时跳过详情页，直接按上次进度进阅读器；
/// 听书/短剧仍进详情页（它们不是「阅读」），详情页加载失败时也停留在
/// 详情页，让用户看到错误与重试。
class BookOpenPreferences {
  BookOpenPreferences._();

  static final BookOpenPreferences instance = BookOpenPreferences._();

  static const _key = 'book_open_direct_reader';

  /// Whether tapping a book opens the reader directly. Loaded from
  /// SharedPreferences by [load]; before that completes it reads the
  /// default (detail page first).
  final ValueNotifier<bool> directReader = ValueNotifier<bool>(false);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      directReader.value = sp.getBool(_key) ?? false;
    } catch (_) {
      // A broken optional preference reads as the default (detail first).
    }
  }

  /// 忘掉已加载状态，让下一次 [load] 重新读 SharedPreferences。
  ///
  /// 只为测试存在：`_loaded` 是进程级一次性守卫，`setMockInitialValues`
  /// 换掉的初值不会被已加载过的实例重新读取。
  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    directReader.value = false;
  }

  Future<void> set(bool value) async {
    directReader.value = value;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_key, value);
    } catch (_) {
      // The in-session value still applies; only persistence failed.
    }
  }
}
