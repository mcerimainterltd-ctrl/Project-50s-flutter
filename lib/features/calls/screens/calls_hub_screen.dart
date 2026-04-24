import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'call_history_screen.dart';
import '../../../core/theme/app_theme.dart';

class CallsHubScreen extends ConsumerStatefulWidget {
  const CallsHubScreen({super.key});
  @override
  ConsumerState<CallsHubScreen> createState() => _CallsHubScreenState();
}

class _CallsHubScreenState extends ConsumerState<CallsHubScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: XameColors.darkBg,
      body: const CallHistoryScreen(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: XameColors.darkSurface,
          border: Border(top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06)))),
        child: SafeArea(
          child: Row(children: [
            _NavItem(
              icon: Icons.history_rounded,
              label: 'Call History',
              selected: _tab == 0,
              onTap: () => setState(() => _tab = 0)),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     selected;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              color: selected ? XameColors.primary : Colors.white38,
              size: 24),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: selected ? XameColors.primary : Colors.white38,
                  fontSize: 11,
                  fontWeight: selected
                      ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    ),
  );
}
