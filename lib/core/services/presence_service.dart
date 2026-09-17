import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/constants.dart';

class PresenceService {
  static const MethodChannel _channel =
      MethodChannel('com.xamepage.app/presence');

  static const FlutterSecureStorage _secureStorage =
      FlutterSecureStorage();

  static Future<void> start(String xameId) async {
    final id = xameId.trim();
    if (id.isEmpty) return;

    try {
      final sessionToken =
          await _secureStorage.read(key: AppConstants.keySessionToken);

      if (sessionToken == null || sessionToken.isEmpty) return;

      await _channel.invokeMethod<void>('start', {
        'userId': id,
        'sessionToken': sessionToken,
      });
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
