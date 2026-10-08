import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import 'auth_service.dart';

final xameTelVoiceServiceProvider = Provider<XameTelVoiceService>((ref) {
  final service = XameTelVoiceService();
  final user = ref.watch(currentUserProvider);

  service.initialize(userId: user?.xameId);

  ref.onDispose(service.dispose);
  return service;
});

class XameTelEvent {
  final String event;
  final String callSid;
  final String? from;
  final String? to;

  const XameTelEvent({
    required this.event,
    required this.callSid,
    this.from,
    this.to,
  });

  factory XameTelEvent.fromMap(Map<dynamic, dynamic> map) {
    return XameTelEvent(
      event: map['event'] as String? ?? '',
      callSid: map['callSid'] as String? ?? '',
      from: map['from'] as String?,
      to: map['to'] as String?,
    );
  }
}

class XameTelVoiceService {
  static const MethodChannel _channel =
      MethodChannel('com.xamepage.app/xametel');

  final StreamController<XameTelEvent> _eventController =
      StreamController<XameTelEvent>.broadcast();

  bool _initialized = false;
  String? _registeredUserId;
  StreamSubscription<String>? _tokenRefreshSubscription;

  Stream<XameTelEvent> get events => _eventController.stream;

  void initialize({String? userId}) {
    if (!_initialized) {
      _initialized = true;

      _channel.setMethodCallHandler(_handleNativeCall);

      Future<void>(() async {
        try {
          await _channel.invokeMethod<bool>('xametelReady');
        } catch (_) {
          // Native side safely queues events until Flutter becomes ready.
        }
      });
    }

    if (defaultTargetPlatform != TargetPlatform.android ||
        userId == null ||
        userId.isEmpty ||
        userId == _registeredUserId) {
      return;
    }

    _registeredUserId = userId;

    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _registerForIncomingCalls(
        userId: userId,
        fcmToken: token,
      );
    });

    _registerCurrentFcmToken(userId);
  }

  Future<void> _registerCurrentFcmToken(String userId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await _registerForIncomingCalls(
        userId: userId,
        fcmToken: token,
      );
    } catch (_) {}
  }

  Future<bool> _registerForIncomingCalls({
    required String userId,
    required String fcmToken,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.serverUrl}/api/pstn/token/$userId'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      final accessToken = data['token'] as String?;

      if (data['success'] != true ||
          accessToken == null ||
          accessToken.isEmpty) {
        return false;
      }

      final registered = await _channel.invokeMethod<bool>(
        'registerForIncomingCalls',
        {
          'accessToken': accessToken,
          'fcmToken': fcmToken,
        },
      );

      return registered == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> acceptIncomingCall(String callSid) async {
    if (callSid.isEmpty) return false;

    try {
      final result = await _channel.invokeMethod<bool>(
        'acceptIncomingCall',
        {'callSid': callSid},
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rejectIncomingCall(String callSid) async {
    if (callSid.isEmpty) return false;

    try {
      final result = await _channel.invokeMethod<bool>(
        'rejectIncomingCall',
        {'callSid': callSid},
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disconnectActiveCall(String callSid) async {
    if (callSid.isEmpty) return false;

    try {
      final result = await _channel.invokeMethod<bool>(
        'disconnectActiveCall',
        {'callSid': callSid},
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'xametelEvent') return;

    final arguments = call.arguments;
    if (arguments is! Map) return;

    final event = XameTelEvent.fromMap(arguments);
    if (event.event.isEmpty || event.callSid.isEmpty) return;

    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _eventController.close();
  }
}
