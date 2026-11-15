import 'package:flutter/services.dart';
import 'secure_key_storage.dart';

/// HarmonyOS uses a non-exportable HUKS wrapping key. Errors propagate so a
/// missing keystore never becomes a normal empty library.
class HarmonySecureKeyStorage implements SecureKeyStorage {
  const HarmonySecureKeyStorage();
  static const _channel = MethodChannel('fqapp/secure_keys');
  @override
  Future<String?> read(String key) =>
      _channel.invokeMethod<String>('read', {'key': key});
  @override
  Future<void> write(String key, String value) =>
      _channel.invokeMethod<void>('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) =>
      _channel.invokeMethod<void>('delete', {'key': key});
}
