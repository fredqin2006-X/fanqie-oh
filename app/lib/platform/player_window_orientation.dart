import 'dart:io';

import 'package:flutter/services.dart';

/// Uses the main Harmony window directly, independently of system bar changes.
class PlayerWindowOrientation {
  const PlayerWindowOrientation({this.harmony});

  final bool? harmony;
  static const _channel = MethodChannel('fqapp/display');

  Future<void> set(DeviceOrientation? orientation) async {
    assert(
      orientation == null ||
          orientation == DeviceOrientation.portraitUp ||
          orientation == DeviceOrientation.landscapeLeft,
    );
    if (harmony ?? Platform.operatingSystem == 'ohos') {
      try {
        await _channel.invokeMethod<void>('setOrientation', {
          'orientation': switch (orientation) {
            DeviceOrientation.landscapeLeft => 'landscape',
            DeviceOrientation.portraitUp => 'portrait',
            _ => 'restore',
          },
        });
        return;
      } on MissingPluginException {
        // Allows running with an older embedding during development.
      }
    }
    await SystemChrome.setPreferredOrientations([?orientation]);
  }
}
