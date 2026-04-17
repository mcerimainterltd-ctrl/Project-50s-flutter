import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/router.dart';
import 'core/services/socket_service.dart';
import 'core/services/webrtc_service.dart';
import 'core/services/auth_service.dart';
import 'shared/models/xame_user.dart';

class XamePageApp extends ConsumerStatefulWidget {
  const XamePageApp({Key? key}) : super(key: key);

  @override
  ConsumerState<XamePageApp> createState() => _XamePageAppState();
}

class _XamePageAppState extends ConsumerState<XamePageApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(webRTCServiceProvider).onIncomingCall.listen((incoming) {
        // Handle incoming call
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    
    if (user != null) {
      ref.read(socketServiceProvider).connect(user.xameId);
    }

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'XamePage',
      routerConfig: ref.watch(routerProvider),
    );
  }
}
