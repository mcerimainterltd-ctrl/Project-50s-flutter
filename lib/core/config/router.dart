import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xamepage/features/discovery/screens/people_discovery_screen.dart';
import 'package:xamepage/features/wallet/screens/xame_pay_screen.dart';
import 'package:xamepage/features/home/screens/home_screen.dart';
import 'package:xamepage/features/calls/screens/call_history_screen.dart';

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