import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerHarmonyPlayerLicenses() {
  if (Platform.operatingSystem != 'ohos') return;
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/licenses/ijkplayer/LICENSE');
    final notice = await rootBundle.loadString('assets/licenses/ijkplayer/NOTICE');
    yield LicenseEntryWithLineBreaks(
      const ['ijkplayer (HarmonyOS)', 'FFmpeg', 'SoundTouch'],
      '$notice\n\n$license',
    );
  });
}
