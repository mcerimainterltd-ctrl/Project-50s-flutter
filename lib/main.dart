import "package:cloud_firestore/cloud_firestore.dart";
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
import 'core/services/cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Write startup marker to Downloads for debugging
  try {
    final file = File('/storage/emulated/0/Download/startup.txt');
    await file.writeAsString('Started at ${DateTime.now()}\n');
  } catch (e) {}
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await Hive.initFlutter();
  await CacheService.init();

  // Initialize Firebase
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

  // Step 89: Initialize Live Data (Seeding)
  try {
    await FirebaseFirestore.instance.collection('broadcasts').doc('live_match_1').set({
      'isLive': true,
      'homeTeam': 'Arsenal',
      'awayTeam': 'Man City',
      'score': '2 - 1',
      'matchTime': "74'",
      'videoUrl': 'https://assets.mixkit.co/videos/preview/mixkit-playing-football-in-the-grass-4442-large.mp4',
      'posterUrl': 'https://images.unsplash.com/photo-1574629810360-7efbbe195018',
    }, SetOptions(merge: true));
  } catch (e) {
    print('Firestore Seed Error: $e');
  }

  XameUser? savedUser;
  try {
    const storage = FlutterSecureStorage();
    final raw = await storage.read(key: AppConstants.keyUser);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['xameId'] != null) savedUser = XameUser.fromMap(map);
    }
  } catch (_) {}

  // Init push service if user is logged in
  if (savedUser != null) {
    final pushService = PushService();
    pushService.init(savedUser!.xameId);
  }

  runApp(ProviderScope(
    overrides: [
      if (savedUser != null)
        currentUserProvider.overrideWith((ref) => savedUser),
    ],
    child: const XamePageApp(),
  ));
}
