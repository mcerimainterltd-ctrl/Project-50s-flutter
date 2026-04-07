import "package:go_router/go_router.dart";
import "core/services/webrtc_service.dart";
import "package:flutter/material.dart";
import "features/calls/screens/call_screen.dart";
import "package:Project_50s_final/features/calls/screens/call_screen.dart";
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/config/constants.dart';
import 'core/services/auth_service.dart';
import 'shared/models/xame_user.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await Hive.initFlutter();
  XameUser? savedUser;
  try {
    const storage = FlutterSecureStorage();
    final raw = await storage.read(key: AppConstants.keyUser);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['xameId'] != null) savedUser = XameUser.fromMap(map);
    }
  } catch (_) {}
  runApp(ProviderScope(
    overrides: [
      if (savedUser != null)
        currentUserProvider.overrideWith((ref) => savedUser!),
    ],
    child: const XamePageApp(),
  ));
}
