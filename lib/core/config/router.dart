import '../../shared/widgets/pin_lock_screen.dart';
import '../../core/services/wallet_lock_service.dart';
import '../../core/services/app_lock_service.dart';
import "../../features/discovery/screens/people_discovery_screen.dart";
import "../../features/discovery/screens/discovery_aura_feed.dart";
import "../../features/tv/screens/xame_tv_page.dart";
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../config/constants.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/contacts/screens/contacts_screen.dart';
import '../../features/messaging/screens/chat_screen.dart';
import '../../features/calling/screens/call_screen.dart';
import '../../features/calling/screens/incoming_call_screen.dart';
import '../../features/calls/screens/call_history_screen.dart';
import '../../features/contacts/screens/contact_requests_screen.dart';
import '../../features/contacts/screens/contact_requests_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/settings/screens/settings_lock_screen.dart';
import '../../core/services/settings_lock_service.dart';
import '../../screens/xame_pay_screen.dart';
import '../../features/contacts/providers/contacts_provider.dart';
import '../../screens/phone_screen.dart';
import 'package:xamepage/core/theme/app_theme.dart';

class _Placeholder extends StatelessWidget {
  final String name;
  _Placeholder(this.name);
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.xBg,
    body: Center(child: Text(name,
      style: TextStyle(color: XameColors.darkBg, fontSize: 18))));
}

final routerProvider = Provider<GoRouter>((ref) {
  final user = ref.watch(currentUserProvider);
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loggedIn    = user != null;
      final isAuthRoute = state.matchedLocation == '/login' ||
                          state.matchedLocation == '/register';
      if (!loggedIn && !isAuthRoute) return '/login';
      if (loggedIn  &&  isAuthRoute) return '/contacts';
      return null;
    },
    routes: [
      GoRoute(path: "/discovery", name: "discovery", builder: (context, state) {
          final authorId = state.uri.queryParameters['authorId'];
          return DiscoveryAuraFeed(authorId: authorId);
        }),
      GoRoute(path: "/tv", name: "tv", builder: (context, state) => const XameTVPage()),
      GoRoute(path: "/people", name: "people", builder: (c, s) => const PeopleDiscoveryScreen()),
      GoRoute(path: '/login',    builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
      GoRoute(path: '/contacts', builder: (c, s) => const ContactsScreen()),
      GoRoute(path: '/chat/:userId',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final sharedFiles = extra?['sharedFiles'] as List<dynamic>?;
          return ChatScreen(
            userId: s.pathParameters['userId']!,
            sharedFiles: sharedFiles,
          );
        }),
      GoRoute(path: '/call/:userId',
        builder: (context, state) => CallScreen(
          userId: state.pathParameters['userId']!,
          isVideo: state.uri.queryParameters['video'] == 'true',
          isIncoming: state.uri.queryParameters['incoming'] == 'true',
        )),
      GoRoute(path: '/incoming-call',
        builder: (context, state) => const IncomingCallScreen()),
      GoRoute(path: '/conference',    builder: (c, s) => _Placeholder('Conference')),
      GoRoute(path: '/call-history',  builder: (c, s) => CallHistoryScreen(onBack: () => c.go('/contacts'))),
      GoRoute(path: '/contact-requests', builder: (c, s) => const ContactRequestsScreen()),
      GoRoute(path: '/contact-requests', builder: (c, s) => const ContactRequestsScreen()),
      GoRoute(path: '/dialpad',       builder: (c, s) => PhoneScreen(userId: ref.read(currentUserProvider)?.xameId ?? '', serverUrl: AppConstants.serverUrl)),
      GoRoute(path: '/app-lock', builder: (c, s) {
        final notifier = ref.read(appLockProvider.notifier);
        return PopScope(
          canPop: false,
          child: PinLockScreen(
            title:    'XamePage Locked',
            subtitle: 'Enter your PIN to continue',
            icon:     '🔐',
            pinLength: 6,
            showCancel: false,
            autoBiometric: true,
            onVerify: (pin) async {
              final ok = notifier.verify(pin);
              if (ok) c.pop();
              return ok;
            },
            onForgot: () async {
              await notifier.disable();
              c.pop();
            },
          ),
        );
      }),
      GoRoute(path: '/wallet-lock', builder: (c, s) {
        final notifier = ref.read(walletLockProvider.notifier);
        return PinLockScreen(
          title:    'XamePay Wallet',
          subtitle: 'Enter your wallet PIN',
          icon:     '💰',
          pinLength: 4,
          showCancel: true,
          autoBiometric: true,
          onCancel: () => c.go('/contacts'),
          onVerify: (pin) async {
            final ok = notifier.verify(pin);
            if (ok) c.go('/wallet');
            return ok;
          },
        );
      }),
      GoRoute(path: '/wallet', builder: (c, s) {
        final user     = ref.read(currentUserProvider);
        final contacts = ref.read(contactsProvider).valueOrNull ?? [];
        final xameContacts = contacts
          .where((ct) => ct.id != user?.xameId)
          .map((ct) => <String,String>{'id': ct.id, 'name': ct.name})
          .toList();
        return XamePayScreen(
          userId:       user?.xameId ?? '',
          serverUrl:    AppConstants.serverUrl,
          onBack:       () => c.go('/contacts'),
          xameContacts: xameContacts,
        );
      }),
      GoRoute(path: '/settings', builder: (c, s) {
        final lockState = ref.read(settingsLockProvider);
        if (!lockState.enabled || lockState.pin.isEmpty) return const SettingsScreen();
        // Always show lock screen on every visit — unlocks via push so
        // navigating away re-locks automatically next visit.
        return SettingsLockScreen(
          pinLength: 4,
          onBack: () => c.go('/contacts'),
          onVerify: (pin) async {
            final ok = ref.read(settingsLockProvider.notifier).verify(pin);
            if (ok) {
              // Replace lock screen with settings in the same route slot
              Navigator.of(c).pushReplacement(
                MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }
            return ok;
          },
          onForgot: () async {
            await ref.read(settingsLockProvider.notifier).disable();
            Navigator.of(c).pushReplacement(
              MaterialPageRoute(builder: (_) => const SettingsScreen()));
          },
        );
      }),
      GoRoute(path: '/profile',       builder: (c, s) => const ProfileScreen()),    ],
  );
});
// ignore: unused_import
