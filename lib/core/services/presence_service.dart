import 'package:flutter/services.dart';

class PresenceService {
  static const MethodChannel _channel =
      MethodChannel('com.xamepage.app/presence');

  static Future<void> start(String xameId) async {
    if (xameId.trim().isEmpty) return;

    try {
      await _channel.invokeMethod<void>('start', {
        'userId': xameId.trim(),
      });
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
