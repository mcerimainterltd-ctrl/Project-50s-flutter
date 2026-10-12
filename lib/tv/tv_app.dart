// lib/tv/tv_app.dart
// Android TV / Fire TV entry: opens straight into XameTV.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/services/cache_service.dart';
import '../features/tv/screens/xame_tv_page.dart';

Future<void> runTvApp() async {
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  try {
    await Hive.initFlutter();
    await CacheService.init();
  } catch (_) {}
  runApp(const TvApp());
}

class TvApp extends StatelessWidget {
  const TvApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'XameTV',
      theme: ThemeData.dark(),
      home: const _TvLauncher(),
    );
  }
}

class _TvLauncher extends StatefulWidget {
  const _TvLauncher();

  @override
  State<_TvLauncher> createState() => _TvLauncherState();
}

class _TvLauncherState extends State<_TvLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const XameTVPage()),
      );
      SystemNavigator.pop();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: Color(0xFF0A0A0F));
}
