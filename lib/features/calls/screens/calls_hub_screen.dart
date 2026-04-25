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
      backgroundColor: const Color(0xFF0A0A0F),
      body: IndexedStack(index: _tab, children: const [
        CallHistoryScreen(),
        _CallScheduleTab(),
        _ConferenceTab(),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141420),
          border: Border(top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06)))),
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
              color: selected ? const Color(0xFF00D4FF) : Colors.white38,
              size: 24),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: selected ? const Color(0xFF00D4FF) : Colors.white38,
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
  const _CallScheduleTab();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0A0A0F),
    body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E), shape: BoxShape.circle,
            border: Border.all(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.3))),
          child: Icon(Icons.schedule_outlined,
              color: const Color(0xFF00D4FF), size: 56)),
        const SizedBox(height: 24),
        const Text('Call Schedule',
            style: TextStyle(color: Colors.white,
                fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Schedule calls with your contacts',
            style: TextStyle(color: Colors.white38, fontSize: 14),
            textAlign: TextAlign.center),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('Schedule a Call',
              style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D4FF),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        ),
      ],
    )),
  );
}

// ── Conference Tab ────────────────────────────────────────────────────────────
class _ConferenceTab extends StatelessWidget {
  const _ConferenceTab();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0A0A0F),
    body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E), shape: BoxShape.circle,
            border: Border.all(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.3))),
          child: Icon(Icons.groups_rounded,
              color: const Color(0xFF00D4FF), size: 56)),
        const SizedBox(height: 24),
        const Text('Conference Call',
            style: TextStyle(color: Colors.white,
                fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Start a call with multiple contacts at once',
            style: TextStyle(color: Colors.white38, fontSize: 14),
            textAlign: TextAlign.center),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add_call),
          label: const Text('Start Conference',
              style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D4FF),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        ),
      ],
    )),
  );
}
