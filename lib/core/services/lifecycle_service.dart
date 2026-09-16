import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'socket_service.dart';
import 'webrtc_service.dart';
import 'audio_service.dart';
import 'auth_service.dart';
import 'push_service.dart';
import 'storage_health_service.dart';

final lifecycleServiceProvider = Provider<LifecycleService>((ref) {
  return LifecycleService(ref);
});

class LifecycleService with WidgetsBindingObserver {
  final Ref _ref;
  bool _wasConnected = true;
  bool _connectivityEventSeen = false;
  StreamSubscription? _connectivitySub;

  LifecycleService(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    _listenConnectivity();
    _initializeConnectivity();
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
        // Don't disconnect socket — keep user online
        debugPrint('XamePage: App backgrounded — maintaining presence');
        break;

      case AppLifecycleState.resumed:
        // App coming to foreground
        if (user != null) {
          if (socket.isConnected) {
            socket.emitUserOnline(user.xameId);
            socket.emitRequestOnlineUsers();
            socket.startHeartbeat(user.xameId);
          } else {
            // Reconnect and restart heartbeat
            socket.connect(user.xameId);
            socket.startHeartbeat(user.xameId);
          }
          // Always re-save FCM token on foreground
          final push = _ref.read(pushServiceProvider);
          push.reRegisterToken(user.xameId);
        }

        // Refresh device storage health whenever XamePage returns to foreground.
        _ref.read(storageHealthServiceProvider).checkNow();

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
  Future<void> _initializeConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!_connectivityEventSeen) {
        _wasConnected =
            results.any((r) => r != ConnectivityResult.none);
        debugPrint(
          'XamePage: Initial network state: '
          '${_wasConnected ? 'online' : 'offline'}',
        );
      }
    } catch (e) {
      debugPrint('XamePage: Initial connectivity check failed: $e');
    }
  }

  void _listenConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      _connectivityEventSeen = true;
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      final socket   = _ref.read(socketServiceProvider);
      final user     = _ref.read(currentUserProvider);

      if (isOnline && !_wasConnected) {
        debugPrint('XamePage: Network restored — reconnecting');

        if (user != null) {
          if (!socket.isConnected) {
            socket.connect(user.xameId);
          }

          socket.startHeartbeat(user.xameId);

          if (socket.isConnected) {
            socket.emitUserOnline(user.xameId);
          }

          final push = _ref.read(pushServiceProvider);
          push.reRegisterToken(user.xameId);
        }
      } else if (!isOnline && _wasConnected) {
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
    _connectivitySub?.cancel();
    _connectivitySub = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}
