import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import 'auth_service.dart';

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
      // Flutter routing handled by app.dart socket listener
    });
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
      _showMessageNotification(
        data['senderName'] ?? 'XamePage',
        data['message']   ?? 'New message',
      );
    }
  }

  void _showMessageNotification(String sender, String body) {
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
