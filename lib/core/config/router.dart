import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../../shared/models/xame_user.dart';
import '../services/auth_service.dart';

// Placeholder screens — replace with real screens as you build them
class _Placeholder extends StatelessWidget {
  final String name;
  const _Placeholder(this.name);
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0A0A0F),
    body: Center(child: Text(name, style: const TextStyle(color: Colors.white))));
}

final routerProvider = Provider<GoRouter>((ref) {
  final user = ref.watch(currentUserProvider);
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loggedIn   = user != null;
      final isAuthRoute = state.matchedLocation == '/login' || state.matchedLocation == '/register';
      if (!loggedIn && !isAuthRoute) return '/login';
      if (loggedIn  &&  isAuthRoute) return '/contacts';
      return null;
    },
    routes: [
      GoRoute(path: '/login',        builder: (c, s) => const _Placeholder('Login')),
      GoRoute(path: '/register',     builder: (c, s) => const _Placeholder('Register')),
      GoRoute(path: '/contacts',     builder: (c, s) => const _Placeholder('Contacts')),
      GoRoute(path: '/chat/:userId', builder: (c, s) => _Placeholder('Chat: ${s.pathParameters['userId']}')),
      GoRoute(path: '/call/:userId', builder: (c, s) => _Placeholder('Call: ${s.pathParameters['userId']}')),
      GoRoute(path: '/incoming-call',builder: (c, s) => const _Placeholder('Incoming Call')),
      GoRoute(path: '/conference',   builder: (c, s) => const _Placeholder('Conference')),
      GoRoute(path: '/call-history', builder: (c, s) => const _Placeholder('Call History')),
      GoRoute(path: '/dialpad',      builder: (c, s) => const _Placeholder('Dialpad')),
      GoRoute(path: '/wallet',       builder: (c, s) => const _Placeholder('Wallet')),
      GoRoute(path: '/settings',     builder: (c, s) => const _Placeholder('Settings')),
      GoRoute(path: '/profile',      builder: (c, s) => const _Placeholder('Profile')),
    ],
  );
});
