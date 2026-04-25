import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xamepage/core/config/router.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/services/webrtc_service.dart';
import 'package:xamepage/core/services/auth_service.dart';
import 'package:xamepage/shared/models/xame_user.dart';
import 'package:xamepage/core/theme/app_theme.dart';

class XamePageApp extends ConsumerStatefulWidget {
  const XamePageApp({super.key});
  @override
  ConsumerState<XamePageApp> createState() => _XamePageAppState();
}

class _XamePageAppState extends ConsumerState<XamePageApp> {
  @override
  void initState() {
    super.initState();
    // Listen for calls in a dedicated listener, not the build method
    Future.microtask(() {
      ref.read(webRTCServiceProvider).onIncomingCall.listen((incoming) {
        if (!incoming) return;
        final router = ref.read(routerProvider);
        // Guard: don't push if already on incoming-call screen
        final location = router.routerDelegate.currentConfiguration.uri.toString();
        if (location.contains('incoming-call')) return;
        router.push("/incoming-call");
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user != null) {
      ref.read(socketServiceProvider).connect(user.xameId);
    }

    final theme = ref.watch(themeProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme:      theme.toThemeData(),
      darkTheme:  theme.toThemeData(),
      themeMode:  theme.isDark ? ThemeMode.dark : ThemeMode.light,
    );
  }
}
