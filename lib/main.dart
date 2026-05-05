import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Hive.initFlutter();
  await CacheService.init();
  await Firebase.initializeApp();

  // Multi-Channel Seed Logic
  final batch = FirebaseFirestore.instance.batch();
  final channels = [
    {
      'id': 'match_1',
      'isLive': true,
      'homeTeam': 'Arsenal',
      'awayTeam': 'Man City',
      'score': '2 - 1',
      'matchTime': "74'",
      'videoUrl': 'https://assets.mixkit.co/videos/preview/mixkit-playing-football-in-the-grass-4442-large.mp4',
      'posterUrl': 'https://images.unsplash.com/photo-1574629810360-7efbbe195018',
    },
    {
      'id': 'match_2',
      'isLive': true,
      'homeTeam': 'Real Madrid',
      'awayTeam': 'Barcelona',
      'score': '0 - 0',
      'matchTime': "12'",
      'videoUrl': 'https://assets.mixkit.co/videos/preview/mixkit-footballer-kicking-the-ball-in-the-field-at-night-41551-large.mp4',
      'posterUrl': 'https://images.unsplash.com/photo-1517466787929-bc90951d0974',
    },
    {
      'id': 'match_3',
      'isLive': true,
      'homeTeam': 'Liverpool',
      'awayTeam': 'Chelsea',
      'score': '1 - 3',
      'matchTime': "88'",
      'videoUrl': 'https://assets.mixkit.co/videos/preview/mixkit-soccer-player-kicking-the-ball-4322-large.mp4',
      'posterUrl': 'https://images.unsplash.com/photo-1508098682722-e99c43a406b2',
    }
  ];

  for (var channel in channels) {
    var ref = FirebaseFirestore.instance.collection('broadcasts').doc(channel['id'] as String);
    batch.set(ref, channel, SetOptions(merge: true));
  }
  batch.commit().catchError((e) => print("Batch Seed Error: $e"));

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

  if (savedUser != null) {
    final pushService = PushService();
    pushService.init(savedUser.xameId);
  }

  runApp(ProviderScope(
    overrides: [if (savedUser != null) currentUserProvider.overrideWith((ref) => savedUser)],
    child: XamePageApp(sharedFile: await _getSharedFile()),
  ));
}

Future<Map<String, String>?> _getSharedFile() async {
  try {
    const channel = MethodChannel('com.xamepage.app/share');
    final result = await channel.invokeMapMethod<String, String>('getSharedFile');
    return result;
  } catch (_) {
    return null;
  }
}
