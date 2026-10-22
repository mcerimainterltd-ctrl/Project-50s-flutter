import 'package:flutter/services.dart';

/// Keeps the Android screen awake while at least one owner holds it.
/// Each owner acquires and releases its own claim, so one screen leaving
/// never switches the screen off under another.
class ScreenAwake {
  ScreenAwake._();

  static const MethodChannel _channel =
      MethodChannel('com.xamepage.app/call');
  static final Set<Object> _holders = <Object>{};

  static Future<void> acquire(Object owner) async {
    final wasEmpty = _holders.isEmpty;
    _holders.add(owner);
    if (wasEmpty) {
      try {
        await _channel.invokeMethod('keepScreenOn');
      } catch (_) {}
    }
  }

  static Future<void> release(Object owner) async {
    if (!_holders.remove(owner)) return;
    if (_holders.isEmpty) {
      try {
        await _channel.invokeMethod('releaseScreen');
      } catch (_) {}
    }
  }
}
