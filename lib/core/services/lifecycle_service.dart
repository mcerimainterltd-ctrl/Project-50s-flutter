import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'socket_service.dart';
import 'webrtc_service.dart';
import 'audio_service.dart';
import 'auth_service.dart';

final lifecycleServiceProvider = Provider<LifecycleService>((ref) {
  return LifecycleService(ref);
});

class LifecycleService with WidgetsBindingObserver {
  final Ref _ref;
  bool _wasConnected = true;

  LifecycleService(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    _listenConnectivity();
  }

  // ── App lifecycle ──────────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final socket = _ref.read(socketServiceProvider);
    final webrtc = _ref.read(webRTCServiceProvider);
    final user   = _ref.read(currentUserProvider);

    switch (state) {

      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // App going to background — maintain socket but update foreground flag
        webrtc.isAppForeground = false;
        // Don't disconnect socket — keep user online
        debugPrint('XamePage: App backgrounded — maintaining presence');
        break;

      case AppLifecycleState.resumed:
        // App coming to foreground
        webrtc.isAppForeground = true;
        // Re-emit online presence
        if (socket.isConnected && user != null) {
          socket.emitRequestOnlineUsers();
        } else if (user != null) {
          // Reconnect if dropped
          socket.connect(user.xameId);
        }
        debugPrint('XamePage: App foregrounded — refreshing presence');
        break;

      case AppLifecycleState.detached:
        // App being killed — clean up everything
        _cleanup();
        break;

      default:
        break;
    }
  }

  // ── Network connectivity ───────────────────────────────────────────────────
  void _listenConnectivity() {
    Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      final socket   = _ref.read(socketServiceProvider);
      final user     = _ref.read(currentUserProvider);

      if (isOnline && !_wasConnected) {
        // Network restored
        debugPrint('XamePage: Network restored — reconnecting');
        if (user != null && !socket.isConnected) {
          socket.connect(user.xameId);
        }
      } else if (!isOnline && _wasConnected) {
        // Network lost
        debugPrint('XamePage: Network lost');
      }
      _wasConnected = isOnline;
    });
  }

  // ── Cleanup on exit ────────────────────────────────────────────────────────
  void _cleanup() {
    try {
      final webrtc = _ref.read(webRTCServiceProvider);
      final audio  = _ref.read(audioServiceProvider);
      final socket = _ref.read(socketServiceProvider);

      webrtc.endCall();
      audio.stopAll();
      socket.disconnect();

      debugPrint('XamePage: Cleanup complete');
    } catch (e) {
      debugPrint('XamePage: Cleanup error: \$e');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
