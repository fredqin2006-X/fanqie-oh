import 'package:flutter/material.dart';

/// Persisted theme-mode preference key: 'theme_mode' = 'light'|'dark'|'system'.
const themeModeKey = 'theme_mode';

/// Brand seed color for the whole app (also used by the player slider and
/// the detail page's accent text).
const appSeedColor = Color(0xFFEF5038);

/// Global theme-mode notifier; the settings page writes it, MaterialApp
/// rebuilds with the new mode.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
);

/// Persisted e-ink mode key: 'eink_mode' = bool.
/// #15/#9：墨水屏模式。开启时全应用纯黑白、无毛玻璃、无过渡动画，
/// 避免墨水屏量化灰阶 / 残影。关闭后恢复原主题。
const einkModeKey = 'eink_mode';

/// Global e-ink mode notifier; the settings page writes it, MaterialApp
/// rebuilds with the e-ink theme.
final ValueNotifier<bool> einkModeNotifier = ValueNotifier(false);

/// No page transition: e-ink screens ghost on every animated frame, so
/// route changes must swap instantly instead of sliding / fading.
class _NoPageTransitionBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

ThemeMode themeModeFromName(String? name) {
  switch (name) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// Unified design system and theme factory for fqapp.
class AppTheme {
  static const Color accent = Color(0xFFEF5038);
  static const Color accentStrong = Color(0xFFC73D29);
  static const Color accentDark = Color(0xFFF05E47);

  /// Pure black-on-white theme for e-ink (#15/#9). No tonal / seed palette,
  /// no grey scale except black-on-white, no ripple, no page transition.
  /// Dark mode is intentionally not honoured here: inverted e-ink pages
  /// ghost badly and the issue asks for #FFFFFF surface / #000000 text.
  static ThemeData _createEinkTheme() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Colors.black,
      onPrimary: Colors.white,
      primaryContainer: Colors.white,
      onPrimaryContainer: Colors.black,
      secondary: Colors.black,
      onSecondary: Colors.white,
      secondaryContainer: Colors.white,
      onSecondaryContainer: Colors.black,
      tertiary: Colors.black,
      onTertiary: Colors.white,
      surface: Colors.white,
      onSurface: Colors.black,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerHigh: Colors.white,
      surfaceContainerHighest: Colors.white,
      onSurfaceVariant: Colors.black,
      outline: Colors.black,
      outlineVariant: Colors.black,
      error: Colors.black,
      onError: Colors.white,
      errorContainer: Colors.white,
      onErrorContainer: Colors.black,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoPageTransitionBuilder(),
          TargetPlatform.ohos: _NoPageTransitionBuilder(),
          TargetPlatform.iOS: _NoPageTransitionBuilder(),
          TargetPlatform.macOS: _NoPageTransitionBuilder(),
          TargetPlatform.windows: _NoPageTransitionBuilder(),
          TargetPlatform.linux: _NoPageTransitionBuilder(),
          TargetPlatform.fuchsia: _NoPageTransitionBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Colors.black,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(size: 22, color: Colors.black),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 0.6),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Colors.black, width: 0.6),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          color: Colors.black,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        dragHandleColor: Colors.black,
        dragHandleSize: Size(36, 4),
      ),
      dividerTheme: const DividerThemeData(
        color: Colors.black,
        thickness: 0.6,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: false,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
        subtitleTextStyle: TextStyle(fontSize: 12.5, color: Colors.black),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.black,
        contentTextStyle: const TextStyle(fontSize: 13, color: Colors.white),
      ),
    );
  }

  static ThemeData createTheme(
    Brightness brightness, {
    bool einkMode = false,
  }) {
    if (einkMode) return _createEinkTheme();
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? accentDark : accent;
    final canvas = isDark ? const Color(0xFF151517) : const Color(0xFFFCFAF7);
    final surface = isDark ? const Color(0xFF242427) : Colors.white;
    final surfaceContainerLow =
        isDark ? const Color(0xFF1C1C1F) : const Color(0xFFF7F5F0);
    final surfaceContainer =
        isDark ? const Color(0xFF242428) : const Color(0xFFF2EFE9);
    final surfaceContainerHigh =
        isDark ? const Color(0xFF2C2C32) : const Color(0xFFEBE7DF);
    final ink = isDark ? const Color(0xFFF5F1EB) : const Color(0xFF262522);
    final muted = isDark ? const Color(0xFFA7A39E) : const Color(0xFF706C66);
    final line = isDark ? const Color(0xFF333336) : const Color(0xFFE8E4DE);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF381C17) : const Color(0xFFFFECE8),
      onPrimaryContainer:
          isDark ? const Color(0xFFFFDAD4) : const Color(0xFF410002),
      secondary: isDark ? const Color(0xFFE5806B) : const Color(0xFFD3513B),
      onSecondary: Colors.white,
      secondaryContainer:
          isDark ? const Color(0xFF33201C) : const Color(0xFFFFECE5),
      onSecondaryContainer:
          isDark ? const Color(0xFFFFDAD2) : const Color(0xFF3C0E07),
      tertiary: isDark ? const Color(0xFF7DB3EC) : const Color(0xFF4A90D9),
      onTertiary: Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainerLowest: isDark ? const Color(0xFF0F0F11) : Colors.white,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest:
          isDark ? const Color(0xFF34343A) : const Color(0xFFE4DFD6),
      onSurfaceVariant: muted,
      outline: isDark ? const Color(0xFF7A7670) : const Color(0xFF9E9A92),
      outlineVariant: line,
      error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
      onError: isDark ? const Color(0xFF690005) : Colors.white,
      errorContainer:
          isDark ? const Color(0xFF93000A) : const Color(0xFFFFDAD6),
      onErrorContainer:
          isDark ? const Color(0xFFFFDAD6) : const Color(0xFF410002),
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: ink,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(size: 22, color: ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: line, width: 0.6),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: line, width: 0.6),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: muted,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        dragHandleColor: line,
        dragHandleSize: const Size(36, 4),
      ),
      dividerTheme: DividerThemeData(
        color: line,
        thickness: 0.6,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: false,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 12.5,
          color: muted,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor:
            isDark ? const Color(0xFF2C2C30) : const Color(0xFF2C2825),
        contentTextStyle: const TextStyle(fontSize: 13, color: Colors.white),
      ),
    );
  }
}
