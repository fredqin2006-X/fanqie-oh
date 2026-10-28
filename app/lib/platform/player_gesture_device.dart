import 'package:flutter/services.dart';

/// A window-local brightness lease that never changes the system setting.
class PlayerGestureDevice {
  static const _channel = MethodChannel('fqapp/display');
  static int _nextSession = 0;
  String? _session;
  double? _brightness;
  Future<double?>? _starting;
  Future<void>? _closing;
  bool _disposed = false;
  int _changeGeneration = 0;
  int _appliedChangeGeneration = 0;

  Future<double?> begin() {
    if (_disposed) return Future.value();
    if (_starting case final pending?) return pending;
    if (_brightness case final value?) return Future.value(value);
    final session =
        'player-${DateTime.now().microsecondsSinceEpoch}-${_nextSession++}';
    _session = session;
    return _starting = _begin(session);
  }

  Future<double?> _begin(String session) async {
    try {
      final value = await _channel.invokeMethod<num>('beginPlayerBrightness', {
        'session': session,
      });
      if (_disposed || session != _session) return null;
      if (value == null || !value.isFinite || value < 0 || value > 1) {
        await suspend();
        return null;
      }
      return _brightness = value.toDouble().clamp(0.02, 1);
    } on MissingPluginException {
      if (_session == session) {
        _starting = null;
        _session = null;
      }
      return null;
    } on PlatformException {
      if (_session == session) await suspend();
      return null;
    } finally {
      if (_session == session) _starting = null;
    }
  }

  Future<bool> setBrightness(double value) async {
    final session = _session;
    if (_disposed ||
        session == null ||
        _brightness == null ||
        !value.isFinite) {
      return false;
    }
    final level = value.clamp(0.02, 1.0);
    final generation = ++_changeGeneration;
    try {
      final accepted = await _channel.invokeMethod<bool>(
        'setPlayerBrightness',
        {'session': session, 'brightness': level},
      );
      if (_disposed || session != _session) return false;
      if (accepted != true) {
        await suspend();
        return false;
      }
      if (generation > _appliedChangeGeneration) {
        _appliedChangeGeneration = generation;
        _brightness = level;
      }
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> suspend() {
    final session = _session;
    _session = null;
    _brightness = null;
    _starting = null;
    return session == null ? Future.value() : _end(session);
  }

  Future<void> _end(String session) async {
    try {
      await _channel.invokeMethod<void>('endPlayerBrightness', {
        'session': session,
      });
    } on MissingPluginException {
      // Older embeddings leave window brightness unchanged.
    } on PlatformException {
      // The native lease also restores on window hide or engine detachment.
    }
  }

  Future<void> dispose() {
    _disposed = true;
    return _closing ??= suspend();
  }
}
