import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/services/webrtc_service.dart';
import 'core/services/webrtc_socket_service.dart';
import 'core/config/router.dart';
import 'core/theme/app_theme.dart';

class XamePageApp extends ConsumerWidget {
  const XamePageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final userId = user?.xameId;

    if (userId != null) {
      WebRTCSocketService().connect(userId);
      ref.read(webRTCServiceProvider).onIncomingCall.listen((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(routerProvider).push("/incoming-call");
        });
      });
    }

    return MaterialApp.router(
      title: 'Xamepage',
      theme: AppTheme.light,
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
