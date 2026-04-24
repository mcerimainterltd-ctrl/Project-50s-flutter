import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'call_history_screen.dart';
import '../../../core/theme/app_theme.dart';

class CallsHubScreen extends ConsumerWidget {
  const CallsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: XameColors.darkBg,
      body: const CallHistoryScreen(),
    );
  }
}
