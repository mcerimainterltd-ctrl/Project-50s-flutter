import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/services/webrtc_service.dart';
import 'core/config/router.dart';
import 'core/theme/app_theme.dart';

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
            GoRouter.of(context).push("/incoming-call");
          });
        }
      });
    }

    return MaterialApp.router(
      title: 'Xamepage',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
