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
  static void Function(Map<String, dynamic>)? _onIncomingCall;

  static void setOnIncomingCall(void Function(Map<String, dynamic>) callback) {

    _onIncomingCall = callback;

  }
  final _fcm   = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;
  String? _pendingRoute;

  static const _headsUpChannelId   = 'xamepage_headsup';
  static const _headsUpChannelName = 'XamePage Calls';
  static const _msgChannelId       = 'xamepage_messages';
  static const _msgChannelName     = 'XamePage Messages';
  static const _alertChannelId     = 'xamepage_alerts';
  static const _alertChannelName   = 'XamePage Alerts';

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
    // Delete old channels so Android picks up new silent settings
    final plugin0 = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    for (final oldId in ['xamepage_call_channel', 'xamepage_headsup_v2']) {
      await plugin0?.deleteNotificationChannel(oldId);
    }

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
    const alerts = AndroidNotificationChannel(
      _alertChannelId,
      _alertChannelName,
      description: 'Wallet, contact requests and system alerts',
      importance: Importance.high,
      playSound: true,
      showBadge: true,
    );
    await plugin?.createNotificationChannel(headsUp);
    await plugin?.createNotificationChannel(messages);
    await plugin?.createNotificationChannel(alerts);
  }

  void _handleForeground(RemoteMessage msg) {
    final data = msg.data;
    final type = data['type'];
    if (type == 'incoming_call' || type == 'incoming-call') { _onIncomingCall?.call(Map<String, dynamic>.from(data)); return; }
    if (type == 'message') {
      final settings = SettingsNotifier.currentSettings;
      if (!settings.msgSound && !settings.msgVibration) return;
      _showMessageNotification(
        data['senderName'] ?? 'XamePage',
        settings.msgPreview ? (data['message'] ?? 'New message') : 'New message',
      );
    }
    if (type == 'contact_request') {
      final settings = SettingsNotifier.currentSettings;
      if (!settings.alertSound) return;
      showAlertNotification(
        '👤 Contact Request',
        '${data['fromName'] ?? 'Someone'} wants to connect with you',
      );
    }
    if (type == 'wallet_credit') {
      final settings = SettingsNotifier.currentSettings;
      if (!settings.alertSound) return;
      showAlertNotification(
        '💰 Wallet Credited',
        data['message'] ?? 'Your wallet has been credited',
      );
    }
    if (type == 'wallet_debit') {
      final settings = SettingsNotifier.currentSettings;
      if (!settings.alertSound) return;
      showAlertNotification(
        '💸 Wallet Debited',
        data['message'] ?? 'A debit was made from your wallet',
      );
    }
    if (type == 'wallet_request') {
      final settings = SettingsNotifier.currentSettings;
      if (!settings.alertSound) return;
      showAlertNotification(
        '🙏 Payment Request',
        '${data['fromName'] ?? 'Someone'} is requesting ${data['currency'] ?? ''} ${data['amount'] ?? ''}',
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

  void showAlertNotification(String title, String body) {
    _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _alertChannelId, _alertChannelName,
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          icon: '@mipmap/ic_launcher',
          playSound: true,
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

  Future<void> reRegisterToken(String userId) async {
    try {
      final token = await _fcm.getToken();
      if (token != null) await _saveToken(userId, token);
    } catch (_) {}
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
