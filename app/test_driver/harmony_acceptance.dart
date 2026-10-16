// Explicit debug-only entrypoint: starts the unmodified original application.
// No diagnostic screen or production menu is added. Normal main has no hooks.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fqapp/main.dart' as original;
import 'package:fqapp/services/native_player.dart';
import 'package:fqapp/services/reader_device.dart';
import 'package:fqapp/services/system_tts.dart';

NativePlayer? _player;
ReaderDevice? _reader;
StreamSubscription<dynamic>? _tts;
final List<String> _ttsEvents = [];

void main() {
  if (!kDebugMode) throw StateError('Acceptance entrypoint is debug-only');
  original.main();
  developer.registerExtension('ext.fqapp.acceptance', (method, args) async {
    try {
      final value = await _run(args);
      return developer.ServiceExtensionResponse.result(jsonEncode(value));
    } catch (error) {
      // Deliberately omit URLs, keys, user text and raw exception payloads.
      return developer.ServiceExtensionResponse.result(jsonEncode({
        'ok': false, 'kind': error.runtimeType.toString(),
        if (error is PlatformException) 'code': error.code,
      }));
    }
  });
}

Future<Map<String, Object?>> _run(Map<String, String> args) async {
  switch (args['action']) {
    case 'playerStart':
      await _player?.dispose();
      final encrypted = args['encrypted'] == 'true';
      final player = _player = NativePlayer();
      await player.create('http://127.0.0.1:19090/${encrypted ? 'encrypted' : 'clear'}.mp4',
          encrypted ? '00112233445566778899aabbccddeeff' : '');
      await player.play();
    case 'playerPause': await _player!.pause();
    case 'playerResume': await _player!.play();
    case 'playerSeek': await _player!.seek(Duration(milliseconds: int.parse(args['positionMs']!)));
    case 'playerRate': await _player!.setRate(double.parse(args['rate']!));
    case 'playerDispose': await _player?.dispose(); _player = null;
    case 'readerStart':
      _reader ??= ReaderDevice();
      await _reader!.start(followSystem: false, brightness: 0.4);
      await _reader!.keepScreenOn(true);
      await _reader!.setImmersive(true);
    case 'readerStop': await _reader?.close(); _reader = null;
    case 'ttsStart':
      _ttsEvents.clear();
      _tts ??= SystemTts.events.listen((value) {
        if (value is Map && value['type'] is String) _ttsEvents.add(value['type'] as String);
      });
      await SystemTts.initialize(const SystemTtsPreferences());
      await SystemTts.speak('鸿蒙应用中文朗读验证。保持原来的阅读界面。', 'harmonyAcceptance');
    case 'ttsStop': await SystemTts.shutdown();
    case 'backgroundStart':
      await NativePlayer.startListenForeground(title: 'fqapp 验证', episode: '系统媒体会话', playing: true, hasPrev: true, hasNext: true, positionMs: 0, durationMs: 15000);
    case 'backgroundStop': await NativePlayer.stopListenForeground();
    case 'status': break;
    default: throw ArgumentError('Unsupported acceptance action');
  }
  return {'ok': true, 'player': _player == null ? null : {
    'playing': _player!.playing, 'firstFrame': _player!.firstFrameRendered,
    'positionMs': _player!.position.inMilliseconds, 'durationMs': _player!.duration.inMilliseconds,
    'width': _player!.videoWidth, 'height': _player!.videoHeight,
    'error': _player!.lastError != null,
  }, 'ttsEvents': List<String>.of(_ttsEvents)};
}
