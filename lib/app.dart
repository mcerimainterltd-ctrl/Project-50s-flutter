import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xamepage/core/config/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xamepage/core/config/router.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:xamepage/core/services/app_lock_service.dart';
import 'package:xamepage/shared/widgets/pin_lock_screen.dart';
import 'dart:async';
import 'package:xamepage/core/services/socket_service.dart';
import 'package:xamepage/core/services/lifecycle_service.dart';
import 'package:xamepage/core/services/webrtc_service.dart';
import 'package:xamepage/core/services/auth_service.dart';
import 'package:xamepage/core/services/update_service.dart';
import 'package:xamepage/shared/models/xame_user.dart';
import 'package:xamepage/core/theme/app_theme.dart';
import 'package:xamepage/features/contacts/providers/contacts_provider.dart';
import 'package:xamepage/features/calls/screens/call_history_screen.dart';
import 'package:xamepage/core/services/cache_service.dart';

const _keepaliveChannel = MethodChannel('com.xamepage.app/keepalive');

class XamePageApp extends ConsumerStatefulWidget {
  const XamePageApp({super.key});
  @override
  ConsumerState<XamePageApp> createState() => _XamePageAppState();
}

class _XamePageAppState extends ConsumerState<XamePageApp> {
  StreamSubscription? _shareSub;
  DateTime? _hiddenAt;
  bool _showingLock = false;
  Timer? _inactivityTimer;

  void _showAppLock() {
    if (_showingLock) return;
    _showingLock = true;
    _inactivityTimer?.cancel();
    final router = ref.read(routerProvider);
    router.push('/app-lock').then((_) {
      _showingLock = false;
      _resetInactivityTimer();
    });
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    final lockState = ref.read(appLockProvider);
    if (!lockState.enabled || lockState.pin.isEmpty) return;
    _inactivityTimer = Timer(Duration(milliseconds: lockState.delayMs), _showAppLock);
  }

  @override
  void initState() {
    super.initState();
    _initShareListener();
    _initContactRequestListener();
    _initWalletRequestListener();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());

    // App lock — listen to lifecycle
    SystemChannels.lifecycle.setMessageHandler((msg) async {
      final lockState = ref.read(appLockProvider);
      if (!lockState.enabled || lockState.pin.isEmpty) return null;
      if (msg == 'AppLifecycleState.paused') {
        _hiddenAt = DateTime.now();
        _inactivityTimer?.cancel();
      } else if (msg == 'AppLifecycleState.resumed') {
        if (_showingLock) return null;
        final hidden = _hiddenAt;
        _hiddenAt = null;
        if (hidden != null) {
          final elapsed = DateTime.now().difference(hidden).inMilliseconds;
          if (elapsed >= lockState.delayMs) {
            _showAppLock();
            return null;
          }
        }
        _resetInactivityTimer();
      }
      return null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetInactivityTimer());

    // Keepalive heartbeat — called every 25s by SocketKeepaliveService
    _keepaliveChannel.setMethodCallHandler((call) async {
      if (call.method == 'heartbeat') {
        final user = ref.read(currentUserProvider);
        if (user != null) {
          final socket = ref.read(socketServiceProvider);
          if (socket.isConnected) {
            socket.emitHeartbeat(user.xameId);
          } else {
            // Socket dead — reconnect and restart heartbeat
            socket.connect(user.xameId);
            socket.startHeartbeat(user.xameId);
          }
        }
      }
    });


    // Initialize lifecycle service — handles reconnect on network/resume
    ref.read(lifecycleServiceProvider);

    // Listen for calls in a dedicated listener, not the build method
    // Eager load all data immediately
    Future.microtask(() async {
      // Load contacts immediately
      try { ref.read(contactsProvider); } catch (_) {}
      // Start heartbeat immediately on app start
      final user = ref.read(currentUserProvider);
      if (user != null) {
        ref.read(socketServiceProvider).startHeartbeat(user.xameId);
      }
    });

    Future.microtask(() {
      ref.read(webRTCServiceProvider).onIncomingCall.listen((incoming) {
        final router = ref.read(routerProvider);
        final location = router.routerDelegate.currentConfiguration.uri.toString();
        if (!incoming) {
          // Let IncomingCallScreen handle its own pop via _safePop()
          return;
        }
        // Guard: don't push if already on incoming-call screen
        if (location.contains('incoming-call')) return;
        // Guard: don't push full screen if user is in any chat — banner handles it
        if (location.contains('/chat/')) return;
        router.push("/incoming-call");
      });
    });
  }

  @override
  StreamSubscription? _shareSubscription;
  StreamSubscription? _contactRequestAcceptedSub;


  StreamSubscription? _walletRequestSub;

  void _initWalletRequestListener() {
    _walletRequestSub = ref.read(socketServiceProvider)
        .walletRequest.listen((data) {
      final fromName = data['fromName'] as String? ?? 'Someone';
      final amount   = data['amount'];
      final currency = data['currency'] as String? ?? 'NGN';
      final fromId   = data['fromId']  as String? ?? '';
      final note     = data['note']    as String? ?? '';
      final router = ref.read(routerProvider);
      final ctx = router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null) return;
      showModalBottomSheet(
        context: ctx,
        backgroundColor: const Color(0xFF111E2E),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('💰 Payment Request',
                style: TextStyle(color: Colors.white,
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Text('$fromName is requesting',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            Text('$currency $amount',
                style: const TextStyle(color: Color(0xFF00B0A0),
                    fontSize: 32, fontWeight: FontWeight.w800)),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('"$note"',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Dismiss',
                    style: TextStyle(color: Colors.white54)))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B0A0),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final user = ref.read(currentUserProvider);
                  if (user == null) return;
                  try {
                    final res = await http.post(
                      Uri.parse('${AppConstants.serverUrl}/api/wallet/p2p'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'senderId':    user.xameId,
                        'recipientId': fromId,
                        'amount':      amount,
                        'currency':    currency,
                        'note':        note,
                      }),
                    );
                    final d = jsonDecode(res.body);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(d['success'] == true
                            ? 'Payment sent to $fromName'
                            : d['message'] ?? 'Payment failed'),
                      ));
                    }
                  } catch (_) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Payment failed — check connection')));
                    }
                  }
                },
                child: const Text('Pay Now',
                    style: TextStyle(color: Colors.black,
                        fontWeight: FontWeight.w700)))),
            ]),
          ]),
        ),
      );
    });
  }

  void _initContactRequestListener() {
    _contactRequestAcceptedSub = ref.read(socketServiceProvider)
        .contactRequestAccepted.listen((data) {
      // Refresh contacts when our request is accepted
      ref.invalidate(contactsProvider);
    });
  }

  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    await UpdateService.checkForUpdate(context);
  }

  void _initShareListener() {
    // Handle sharing when app is already open
    _shareSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        if (files.isEmpty) return;
        _handleSharedFiles(files);
      },
    );
    // Handle sharing when app is launched from share
    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> files) {
        if (files.isEmpty) return;
        _handleSharedFiles(files);
        ReceiveSharingIntent.instance.reset();
      },
    );
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    final router = ref.read(routerProvider);
    final contacts = ref.read(contactsProvider).valueOrNull ?? [];
    if (contacts.isEmpty) return;
    showModalBottomSheet(
      context: router.routerDelegate.navigatorKey.currentContext!,
      backgroundColor: const Color(0xFF1A2332),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Share to Contact',
                style: TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w700))),
          const Divider(color: Colors.white12, height: 1),
          SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: contacts.length,
              itemBuilder: (ctx, i) {
                final c = contacts[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF00B0A0),
                    child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.black,
                            fontWeight: FontWeight.bold))),
                  title: Text(c.name,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(c.id,
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    router.push('/chat/${c.id}',
                        extra: {'sharedFiles': files});
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user != null) {
      ref.read(socketServiceProvider).connect(user.xameId);
    }

    // Pre-warm providers when user is logged in
    if (user != null) {
      Future.microtask(() {
        try {
          ref.read(contactsProvider);
          ref.read(callHistoryProvider(user.xameId));
        } catch (_) {}
      });
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
