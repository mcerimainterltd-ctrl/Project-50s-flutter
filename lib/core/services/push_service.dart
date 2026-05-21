import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import 'auth_service.dart';
import '../../features/settings/screens/settings_screen.dart';

final pushServiceProvider = Provider<PushService>((ref) {
  final user = ref.watch(currentUserProvider);
  final service = PushService();
  if (user != null) service.init(user.xameId);
  return service;
});

// Background message handler — must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Handled by XameFirebaseMessagingService.kt on Android
}

class PushService {
  final _fcm   = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;
  String? _pendingRoute;

  static const _headsUpChannelId   = 'xamepage_headsup';
  static const _headsUpChannelName = 'XamePage Calls';
  static const _msgChannelId       = 'xamepage_messages';
  static const _msgChannelName     = 'XamePage Messages';

  Future<void> init(String userId) async {
    // Request permission
    await _fcm.requestPermission(
      alert: true, badge: true, sound: true,
      criticalAlert: true, provisional: false,
    );

    // Init local notifications
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Create notification channels
    await _createChannels();

    // Save token
    final token = await _fcm.getToken();
    if (token != null) await _saveToken(userId, token);

    // Refresh token
    _fcm.onTokenRefresh.listen((t) => _saveToken(userId, t));

    // Foreground messages
    FirebaseMessaging.onMessage.listen((msg) => _handleForeground(msg));

    // Background handler
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    // When app opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final type = msg.data['type'];
      if (type == 'xamepage_news' || type == 'app_update') {
        _navigatorKey?.currentContext != null
            ? _navigatorKey!.currentContext!
                .findRootAncestorStateOfType<NavigatorState>()
            : null;
        _pendingRoute = '/discovery';
      }
    });

    // Check if app was opened from a terminated state via notification
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      final type = initial.data['type'];
      if (type == 'xamepage_news' || type == 'app_update') {
        _pendingRoute = '/discovery';
      }
    }
  }

  Future<void> _createChannels() async {
    const headsUp = AndroidNotificationChannel(
      _headsUpChannelId,
      _headsUpChannelName,
      description: 'Incoming call notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    const messages = AndroidNotificationChannel(
      _msgChannelId,
      _msgChannelName,
      description: 'Message notifications',
      importance: Importance.high,
      playSound: true,
      showBadge: true,
    );
    final plugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.createNotificationChannel(headsUp);
    await plugin?.createNotificationChannel(messages);
  }

  void _handleForeground(RemoteMessage msg) {
    final data = msg.data;
    final type = data['type'];
    if (type == 'incoming_call') return; // Handled by socket
    if (type == 'message') {
      final settings = SettingsNotifier.currentSettings;
      if (!settings.msgSound && !settings.msgVibration) return;
      _showMessageNotification(
        data['senderName'] ?? 'XamePage',
        settings.msgPreview ? (data['message'] ?? 'New message') : 'New message',
      );
    }
    if (type == 'xamepage_news') {
      _showNewsNotification(
        data['title'] ?? 'XamePage News',
        data['version'] ?? '',
      );
    }
    if (type == 'app_update') {
      _showUpdateNotification(
        data['version'] ?? '',
      );
    }
  }

  void _showNewsNotification(String title, String version) {
    _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '📣 XamePage Official',
      title,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _msgChannelId, _msgChannelName,
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  void _showUpdateNotification(String version) {
    _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '🚀 XamePage Update Available',
      version.isNotEmpty ? 'Version $version is ready to download' : 'A new update is available',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _headsUpChannelId, _headsUpChannelName,
          importance: Importance.max,
          priority: Priority.max,
          showWhen: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  void _showMessageNotification(String sender, String body) {
    final settings = SettingsNotifier.currentSettings;
    _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      sender,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _msgChannelId, _msgChannelName,
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          icon: '@mipmap/ic_launcher',
          playSound: settings.msgSound,
          enableVibration: settings.msgVibration,
        ),
      ),
    );
  }

  Future<void> _saveToken(String userId, String token) async {
    try {
      await http.post(
        Uri.parse('\${AppConstants.serverUrl}/api/save-fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'fcmToken': token}),
      );
    } catch (_) {}
  }
}
