import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/services/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/config/constants.dart';
import 'core/services/auth_service.dart';
import 'shared/models/xame_user.dart';
import 'app.dart';
import 'package:app_links/app_links.dart';
import 'core/services/cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parallel initialization for faster startup
  await Future.wait([
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    Hive.initFlutter().then((_) => CacheService.init()),
    Firebase.initializeApp(),
  ]);

  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  
  XameUser? savedUser;
  try {
    const storage = FlutterSecureStorage();
    final raw = await storage.read(key: AppConstants.keyUser);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['xameId'] != null) savedUser = XameUser.fromMap(map);
    }
  } catch (_) {}

  // Init push service without blocking app launch
  if (savedUser != null) {
    PushService().init(savedUser.xameId);
  }

  final appLinks = AppLinks();

  // Handle deep link on cold start
  String? initialDeepLink;
  try {
    final uri = await appLinks.getInitialLink();
    if (uri != null) {
      final segments = uri.pathSegments;
      final first = segments.isNotEmpty ? segments[0] : '';

      // Custom xamepage:// links use the URI host for the action:
      // xamepage://chat/<userId>, xamepage://call/<userId>, etc.
      final action = uri.scheme == 'xamepage' ? uri.host : first;
      final id = uri.scheme == 'xamepage'
          ? (segments.isNotEmpty ? segments[0] : '')
          : (segments.length > 1 ? segments[1] : '');

      if (action == 'join' || uri.queryParameters.containsKey('ref')) {
        final code = action == 'join'
            ? id
            : (uri.queryParameters['ref'] ?? '');
        if (code.isNotEmpty) initialDeepLink = '/register?ref=$code';
      } else if (action == 'chat' && id.isNotEmpty) {
        initialDeepLink = '/chat/$id';
      } else if (action == 'call' && id.isNotEmpty) {
        initialDeepLink = '/call/$id?video=false&incoming=false';
      } else if (action == 'pay' && id.isNotEmpty) {
        initialDeepLink = '/pay/$id';
      } else if (action == 'u' && id.isNotEmpty) {
        initialDeepLink = '/u/$id';
      }
    }
  } catch (_) {}

  runApp(ProviderScope(
    overrides: [if (savedUser != null) currentUserProvider.overrideWith((ref) => savedUser)],
    child: XamePageApp(initialDeepLink: initialDeepLink),
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PushService.setOnIncomingCall((data) {
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushReplacementNamed('/incoming-call', arguments: data);
      }
    });
  });
}
