import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xamepage/core/config/constants.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'features/discovery/screens/collab_thread_screen.dart';
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
import 'package:xamepage/core/services/push_service.dart';
import 'package:xamepage/shared/models/xame_user.dart';
import 'package:xamepage/core/theme/app_theme.dart';
import 'package:xamepage/features/contacts/providers/contacts_provider.dart';
import 'package:xamepage/features/calls/screens/call_history_screen.dart';
import 'package:xamepage/core/services/cache_service.dart';

const _keepaliveChannel = MethodChannel('com.xamepage.app/keepalive');

class XamePageApp extends ConsumerStatefulWidget {
  final String? initialDeepLink;
  const XamePageApp({super.key, this.initialDeepLink});
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
    // Auto-connect socket as soon as user is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        ref.read(socketServiceProvider).connect(user.xameId);
      }
      ref.listenManual(currentUserProvider, (prev, next) {
        if (next != null && prev?.xameId != next.xameId) {
          ref.read(socketServiceProvider).connect(next.xameId);
        }
      });
    });
    _loadOpenedCollabThreads().then((_) => _initCollabListener());
    Future.delayed(const Duration(seconds: 3), _checkPendingCollabThreads);
    // Also check on socket reconnect
    ref.read(socketServiceProvider).connectionState.listen((state) {
      if (state == SocketState.connected) {
        Future.delayed(const Duration(seconds: 2), _checkPendingCollabThreads);
        // Re-subscribe to collab accepted on every reconnect
        _collabAcceptedSub?.cancel();
        _collabAcceptedSub = ref.read(socketServiceProvider).collabAccepted.listen((data) {
          _handleCollabAccepted(data);
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBatteryOptimization());
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFcmNavigation());
    if (widget.initialDeepLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(routerProvider).go(widget.initialDeepLink!);
      });
    }

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
        if (call.method == 'onNetworkAvailable') {
          final user = ref.read(currentUserProvider);
          if (user != null) {
            ref.read(socketServiceProvider).connect(user.xameId);
          }
          return;
        }
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
        // Reward: daily login streak
        try {
          await http.post(
            Uri.parse('${AppConstants.serverUrl}/api/rewards/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': user.xameId}),
          );
        } catch (_) {}
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
  StreamSubscription? _collabRequestSub;
  StreamSubscription? _collabAcceptedSub;
  StreamSubscription? _collabAuthorizedSub;
  StreamSubscription? _collabSubmittedSub;

  void _initWalletRequestListener() {
    _walletRequestSub = ref.read(socketServiceProvider)
        .walletRequest.listen((data) {
      final fromName = data['fromName'] as String? ?? 'Someone';
      final amount   = data['amount'];
      final currency = data['currency'] as String? ?? 'NGN';
      // Heads-up notification with sound
      ref.read(pushServiceProvider).showAlertNotification(
        '🙏 Payment Request',
        '$fromName is requesting $currency $amount',
      );
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

  final Set<String> _openedCollabThreads = {};

  Future<void> _loadOpenedCollabThreads() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('opened_collab_threads') ?? [];
    _openedCollabThreads.addAll(saved);
  }

  Future<void> _persistOpenedCollabThread(String threadId) async {
    _openedCollabThreads.add(threadId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('opened_collab_threads', _openedCollabThreads.toList());
  }

  Future<void> _checkPendingCollabThreads() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final res = await http.get(Uri.parse(
        '${AppConstants.serverUrl}/api/discover/collab/my-threads?userId=${user.xameId}'));
      final data = jsonDecode(res.body);
      if (data['success'] != true) return;
      final threads = data['threads'] as List;
      if (threads.isEmpty) return;
      // Find threads where user is requester, status active, not yet opened,
      // and created more than 60 seconds ago (socket would have delivered if online)
      final now = DateTime.now();
      final pending = threads.where((t) {
        if (t['requesterId'] != user.xameId) return false;
        if (t['status'] != 'active') return false;
        if (_openedCollabThreads.contains(t['threadId'] as String)) return false;
        final createdAt = DateTime.tryParse(t['createdAt']?.toString() ?? '');
        if (createdAt == null) return false;
        return now.difference(createdAt).inSeconds > 10;
      }).toList();
      if (pending.isEmpty) return;
      final ctx = ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
      if (ctx == null) return;
      final thread = pending.first;
      final threadId = thread['threadId'] as String;
      _persistOpenedCollabThread(threadId);
      final postTitle = thread['postTitle'] as String? ?? '';
      // Show snackbar notification instead of auto-opening
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('🤝 Your collab on "$postTitle" was accepted! Tap to open.'),
        backgroundColor: const Color(0xFF1A3A3A),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Open',
          textColor: const Color(0xFF00E5FF),
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => CollabThreadScreen(
              threadId:     threadId,
              postTitle:    postTitle,
              postMediaUrl: thread['postMediaUrl'] as String? ?? '',
              otherUserId:  thread['authorId'] as String? ?? '',
              isAuthor:     false,
            )))),
      ));
    } catch (_) {}
  }

  void _handleCollabAccepted(Map<String, dynamic> data) {
    final postTitle    = data['postTitle']    as String? ?? 'your post';
    final postMediaUrl = data['postMediaUrl'] as String? ?? '';
    final threadId     = data['threadId']     as String? ?? '';
    _openedCollabThreads.add(threadId);
    ref.read(pushServiceProvider).showAlertNotification(
      '🎉 Collab Accepted!',
      'Your collab on "$postTitle" was accepted!',
    );
    final ctx = ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('🤝 Your collab on "$postTitle" was accepted! Tap to open.'),
      backgroundColor: const Color(0xFF1A3A3A),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: 'Open',
        textColor: const Color(0xFF00E5FF),
        onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => CollabThreadScreen(
            threadId:     threadId,
            postTitle:    postTitle,
            postMediaUrl: postMediaUrl,
            otherUserId:  '',
            isAuthor:     false,
          )))),
    ));
  }

  void _initCollabListener() {
    final socket = ref.read(socketServiceProvider);

    _collabRequestSub = socket.collabRequest.listen((data) {
      final requesterName  = data['requesterName']   as String? ?? 'Someone';
      final postTitle      = data['postTitle']        as String? ?? 'your post';
      final requesterAvatar = data['requesterAvatar'] as String? ?? '';
      final mediaUrl       = data['mediaUrl']         as String? ?? '';
      final postId         = data['postId']           as String? ?? '';
      final requesterId    = data['requesterId']      as String? ?? '';

      // Push notification so the author is alerted even if the app is backgrounded
      ref.read(pushServiceProvider).showAlertNotification(
        '🤝 Collab Request',
        '$requesterName wants to collab on "$postTitle"',
      );

      // In-app bottom sheet — mirrors _showCollabRequestSheet in xame_discover_screen
      final ctx = ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
      if (ctx == null) return;
      showModalBottomSheet(
        context: ctx,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF12121E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('🤝 Collab Request',
                style: TextStyle(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Row(children: [
              Container(width: 48, height: 48,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00E5FF), width: 1.5)),
                child: ClipOval(child: requesterAvatar.isNotEmpty
                    ? CachedNetworkImage(imageUrl: requesterAvatar, fit: BoxFit.cover)
                    : Container(color: const Color(0xFF1A2E2E),
                        child: const Icon(Icons.person, color: Colors.white54)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(requesterName, style: const TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.w700)),
                Text('wants to collab on "$postTitle"',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ])),
            ]),
            if (mediaUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              ClipRRect(borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(imageUrl: mediaUrl,
                    height: 160, width: double.infinity, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(height: 160,
                        color: const Color(0xFF1A1A2E),
                        child: const Icon(Icons.image_outlined,
                            color: Colors.white24, size: 40)))),
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
                child: const Text('Decline',
                    style: TextStyle(color: Colors.white54)))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final res = await http.post(
                      Uri.parse('${AppConstants.serverUrl}/api/discover/collab/accept'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'postId':      postId,
                        'authorId':    ref.read(currentUserProvider)?.xameId ?? '',
                        'requesterId': requesterId,
                      }),
                    );
                    final data = jsonDecode(res.body);
                    if (data['success'] == true && ctx.mounted) {
                      Navigator.of(ctx).push(MaterialPageRoute(
                        builder: (_) => CollabThreadScreen(
                          threadId:     data['threadId'] as String,
                          postTitle:    postTitle,
                          postMediaUrl: mediaUrl,
                          otherUserId:  requesterId,
                          isAuthor:     true,
                        )));
                    }
                  } catch (_) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Failed to accept collab'),
                        backgroundColor: Colors.redAccent,
                      ));
                    }
                  }
                },
                child: const Text('Accept 🤝',
                    style: TextStyle(color: Colors.black,
                        fontWeight: FontWeight.w700)))),
            ]),
          ]),
        ),
      );
    });

    _collabAcceptedSub = socket.collabAccepted.listen(_handleCollabAccepted);
    _collabAuthorizedSub = socket.collabAuthorized.listen((data) {
      final title = data['postTitle'] as String? ?? 'your post';
      ref.read(pushServiceProvider).showAlertNotification(
        '🤝 Collab Authorized',
        'Your collab on "\$title" was authorized — you can now submit your part',
      );
    });
    _collabSubmittedSub = socket.collabSubmitted.listen((data) {
      final title = data['postTitle'] as String? ?? 'your post';
      ref.read(pushServiceProvider).showAlertNotification(
        '🤝 Collab Submitted',
        'A contribution was submitted for "\$title" — review it now',
      );
    });
  }

  void _initContactRequestListener() {
    // Incoming contact request
    ref.read(socketServiceProvider).contactRequest.listen((data) {
      final name = data['fromName'] as String? ?? 'Someone';
      ref.read(pushServiceProvider).showAlertNotification(
        '👤 Contact Request',
        '$name wants to connect with you',
      );
    });
    // Contact request accepted
    _contactRequestAcceptedSub = ref.read(socketServiceProvider)
        .contactRequestAccepted.listen((data) {
      ref.invalidate(contactsProvider);
      final name = data['byName'] as String? ?? 'Someone';
      ref.read(pushServiceProvider).showAlertNotification(
        '✅ Contact Request Accepted',
        '$name accepted your contact request',
      );
    });
  }

  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    await UpdateService.checkForUpdate(context);
  }

  Future<void> _checkBatteryOptimization() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final shownVersion = prefs.getString('battery_prompt_version') ?? '';
    final info = await PackageInfo.fromPlatform();
    if (shownVersion == info.version) return;
    // Check if already exempted via native bridge
    try {
      const bridge = MethodChannel('com.xamepage.app/android_bridge');
      final exempt = await bridge.invokeMethod<bool>('isBatteryOptimized') ?? false;
      if (!exempt) return; // already optimized — skip
    } catch (_) {}
    if (!mounted) return;
    await prefs.setString('battery_prompt_version', info.version);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12121A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: const [
          Text('⚡', style: TextStyle(fontSize: 22)),
          SizedBox(width: 8),
          Text('Stay Reachable', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: const Text(
          'To receive calls and messages at all times, allow XamePage to run in the background.\n\nTap \'Fix Now\' and follow the steps - it takes less than a minute.',
          style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              const MethodChannel('com.xamepage.app/android_bridge')
                  .invokeMethod('openBatterySettings');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BCD4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Fix Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Future<void> _initFcmNavigation() async {
    final router = ref.read(routerProvider);

    // App opened from terminated state via notification
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      final type = initial.data['type'];
      if (type == 'xamepage_news' || type == 'app_update') {
        router.go('/discovery');
      }
    }

    // App opened from background via notification tap
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      final type = msg.data['type'];
      if (type == 'xamepage_news' || type == 'app_update') {
        router.go('/discovery');
      }
    });
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

    // Pre-warm providers when user is logged in
    if (user != null) {
      Future.microtask(() {
        try {
          ref.read(contactsProvider);
          ref.read(callHistoryProvider(user.xameId));
          ref.read(pushServiceProvider);
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
