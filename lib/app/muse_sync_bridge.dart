import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MuseSyncBridge {
  static const channel = MethodChannel('verifin/muse_sync');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> setEnabled(bool enabled) async {
    if (supported) await channel.invokeMethod<void>('setEnabled', enabled);
  }

  static Future<void> saveToken(String origin, String token) => channel
      .invokeMethod<void>('saveToken', {'origin': origin, 'token': token});

  static Future<String> readToken(String origin) async =>
      await channel.invokeMethod<String>('readToken', origin) ?? '';
}
