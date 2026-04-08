import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  // Write startup marker to Downloads
  try {
    final file = File('/storage/emulated/0/Download/startup.txt');
    await file.writeAsString('Started at ${DateTime.now()}\n');
  } catch (e) {}

  runZonedGuarded(() async {
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
          currentUserProvider.overrideWith((ref) => savedUser),
      ],
      child: const XamePageApp(),
    ));
  }, (error, stack) async {
    try {
      final file = File('/storage/emulated/0/Download/crash.txt');
      await file.writeAsString('$error\n$stack\n', mode: FileMode.append);
    } catch (e) {}
  });
}
