import 'package:xamepage/core/services/socket_service.dart';
import 'package:flutter/material.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'core/services/auth_service.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'core/services/webrtc_service.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'core/services/socket_service.dart';
import 'package:xamepage/core/services/socket_service.dart';
import 'core/config/router.dart';
import 'package:xamepage/core/services/socket_service.dart';

import 'package:xamepage/core/services/socket_service.dart';
class XamePageApp extends ConsumerStatefulWidget {
import 'package:xamepage/core/services/socket_service.dart';
  const XamePageApp({super.key});
import 'package:xamepage/core/services/socket_service.dart';
  @override
import 'package:xamepage/core/services/socket_service.dart';
  ConsumerState<XamePageApp> createState() => _XamePageAppState();
import 'package:xamepage/core/services/socket_service.dart';
}
import 'package:xamepage/core/services/socket_service.dart';

import 'package:xamepage/core/services/socket_service.dart';
class _XamePageAppState extends ConsumerState<XamePageApp> {
import 'package:xamepage/core/services/socket_service.dart';
  @override
import 'package:xamepage/core/services/socket_service.dart';
  void initState() {
import 'package:xamepage/core/services/socket_service.dart';
    super.initState();
import 'package:xamepage/core/services/socket_service.dart';
    // Listen for calls in a dedicated listener, not the build method
import 'package:xamepage/core/services/socket_service.dart';
    Future.microtask(() {
import 'package:xamepage/core/services/socket_service.dart';
      ref.read(webRTCServiceProvider).onIncomingCall.listen((incoming) {
import 'package:xamepage/core/services/socket_service.dart';
        if (incoming) ref.read(routerProvider).push("/incoming-call");
import 'package:xamepage/core/services/socket_service.dart';
      });
import 'package:xamepage/core/services/socket_service.dart';
    });
import 'package:xamepage/core/services/socket_service.dart';
  }
import 'package:xamepage/core/services/socket_service.dart';

import 'package:xamepage/core/services/socket_service.dart';
  @override
import 'package:xamepage/core/services/socket_service.dart';
  Widget build(BuildContext context) {
import 'package:xamepage/core/services/socket_service.dart';
    final user = ref.watch(currentUserProvider);
import 'package:xamepage/core/services/socket_service.dart';
    if (user != null) {
import 'package:xamepage/core/services/socket_service.dart';
      ref.read(socketServiceProvider).connect(user.xameId);
import 'package:xamepage/core/services/socket_service.dart';
    }
import 'package:xamepage/core/services/socket_service.dart';

import 'package:xamepage/core/services/socket_service.dart';
    return MaterialApp.router(
import 'package:xamepage/core/services/socket_service.dart';
      debugShowCheckedModeBanner: false,
import 'package:xamepage/core/services/socket_service.dart';
      routerConfig: ref.watch(routerProvider),
import 'package:xamepage/core/services/socket_service.dart';
    );
import 'package:xamepage/core/services/socket_service.dart';
  }
import 'package:xamepage/core/services/socket_service.dart';
}
