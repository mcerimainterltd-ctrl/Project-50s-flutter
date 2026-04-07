import "package:go_router/go_router.dart";
import "core/services/webrtc_service.dart";
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/config/router.dart';


bool _isListening = false;

class XamePageApp extends ConsumerWidget {
  const XamePageApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    
    if (!_isListening) {
      _isListening = true;
      WebRTCService.instance.onIncomingCall.listen((incoming) {
        if (incoming) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.push("/incoming-call");
          });
        }
      });
    }
    // Listen for WebRTC Calls
    WebRTCService.instance.onIncomingCall.listen((incoming) {
      if (incoming) GoRouter.of(context).push("/incoming-call");
    });
    final router    = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'XamePage',
      debugShowCheckedModeBanner: false,
      theme:      AppTheme.light,
      darkTheme:  AppTheme.dark,
      themeMode:  themeMode,
      routerConfig: router,
    );
  }
}
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);
