import 'dart:async';

import 'package:flutter/services.dart';

/// Keeps the Android screen awake while at least one owner holds it.
/// Each owner acquires and releases its own claim, so one screen leaving
/// never switches the screen off under another.
class ScreenAwake {
  ScreenAwake._();

  static const MethodChannel _channel =
      MethodChannel('com.xamepage.app/call');
  static final Set<Object> _holders = <Object>{};

  static Timer? _keepAlive;

  static Future<void> _assertFlag() async {
    try {
      await _channel.invokeMethod('keepScreenOn');
    } catch (_) {}
  }

  static Future<void> acquire(Object owner) async {
    _holders.add(owner);
    // Always re-assert: another plugin may have cleared the window flag.
    await _assertFlag();
    _keepAlive ??= Timer.periodic(const Duration(seconds: 10), (_) {
      if (_holders.isNotEmpty) _assertFlag();
    });
  }

  static Future<void> release(Object owner) async {
    if (!_holders.remove(owner)) return;
    if (_holders.isEmpty) {
      _keepAlive?.cancel();
      _keepAlive = null;
      try {
        await _channel.invokeMethod('releaseScreen');
      } catch (_) {}
    }
  }
}
