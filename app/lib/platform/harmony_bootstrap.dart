import 'dart:async';

import 'package:flutter/services.dart';

class BootstrapReport {
  const BootstrapReport({
    required this.apiVersion,
    required this.launchCount,
    required this.fileReused,
    required this.keyReused,
  });

  final int apiVersion;
  final int launchCount;
  final bool fileReused;
  final bool keyReused;

  factory BootstrapReport.fromMap(Map<Object?, Object?> data) {
    final api = data['apiVersion'];
    final count = data['launchCount'];
    if (api is! int ||
        api < 23 ||
        count is! int ||
        count < 1 ||
        data['fileReused'] is! bool ||
        data['keyReused'] is! bool) {
      throw const FormatException('Invalid native bootstrap response');
    }
    return BootstrapReport(
      apiVersion: api,
      launchCount: count,
      fileReused: data['fileReused'] as bool,
      keyReused: data['keyReused'] as bool,
    );
  }
}

abstract final class HarmonyBootstrap {
  static const channel = MethodChannel('fqapp/harmony_bootstrap');

  static Future<BootstrapReport> inspect() async {
    final result = await channel
        .invokeMapMethod<Object?, Object?>('inspect')
        .timeout(const Duration(seconds: 15));
    if (result == null) throw const FormatException('Missing native response');
    return BootstrapReport.fromMap(result);
  }

  static String describeError(Object? error) => switch (error) {
    MissingPluginException() => '鸿蒙原生通道未注册。',
    TimeoutException() => '系统服务响应超时，请稍后重试。',
    PlatformException(:final code) => '系统服务暂不可用（$code）。已有数据保持原状。',
    _ => '平台验证未通过，请检查本地诊断记录。',
  };
}
