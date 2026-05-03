import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'call_history_screen.dart';
import '../../../core/theme/app_theme.dart';
import 'call_schedule_screen.dart';
import 'conference_screen.dart';
import 'package:go_router/go_router.dart';

class CallsHubScreen extends ConsumerStatefulWidget {
  CallsHubScreen({super.key});
  @override
  ConsumerState<CallsHubScreen> createState() => _CallsHubScreenState();
}

class _CallsHubScreenState extends ConsumerState<CallsHubScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.xBg,
      body: IndexedStack(index: _tab, children: [
        CallHistoryScreen(onBack: () => context.go('/contacts')),
        _CallScheduleTab(),
        _ConferenceTab(),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.xSurface,
          border: Border(top: BorderSide(
              color: context.xText.withValues(alpha: 0.06)))),
        child: SafeArea(
          child: Row(children: [
            _NavItem(
              icon: Icons.call_outlined,
              label: 'Calls',
              selected: _tab == 0,
              onTap: () => setState(() => _tab = 0)),
            _NavItem(
              icon: Icons.schedule_outlined,
              label: 'Call Schedule',
              selected: _tab == 1,
              onTap: () => setState(() => _tab = 1)),
            _NavItem(
              icon: Icons.groups_rounded,
              label: 'Conference',
              selected: _tab == 2,
              onTap: () => setState(() => _tab = 2)),
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
  _NavItem({required this.icon, required this.label,
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
              color: selected ? context.xPrimary : context.xMuted,
              size: 24),
          SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: selected ? context.xPrimary : context.xMuted,
                  fontSize: 11,
                  fontWeight: selected
                      ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    ),
  );
}

// ── Call Schedule Tab ─────────────────────────────────────────────────────────
class _CallScheduleTab extends StatelessWidget {
  _CallScheduleTab();
  @override
  Widget build(BuildContext context) => const CallScheduleScreen();
}

// ── Conference Tab ────────────────────────────────────────────────────────────
class _ConferenceTab extends StatelessWidget {
  _ConferenceTab();
  @override
  Widget build(BuildContext context) => const ConferenceScreen();
}


