import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// EXACT PATHS FROM YOUR FIND COMMAND
import '../../features/discovery/screens/people_discovery_screen.dart';
import '../../screens/xame_pay_screen.dart';
import '../../screens/home_screen.dart'; 
import '../features/calls/screens/call_history_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/discovery',
    routes: [
      GoRoute(path: '/discovery', builder: (c, s) => const HomeScreen()),
      GoRoute(path: '/call-history', builder: (c, s) => const CallHistoryScreen()),
      GoRoute(
        path: '/wallet',
        builder: (c, s) => XamePayScreen(
          initialTab: 0, 
          onBack: () => c.go('/discovery')
        ),
      ),
      GoRoute(
        path: '/bills',
        builder: (c, s) => XamePayScreen(
          initialTab: 2, 
          onBack: () => c.go('/discovery')
        ),
      ),
      GoRoute(path: '/people', builder: (c, s) => const PeopleDiscoveryScreen()),
    ],
    errorBuilder: (c, s) => const Scaffold(
      body: Center(child: Text('Route Error')),
    ),
  );
});