import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'call_history_screen.dart';
import '../../../core/theme/app_theme.dart';

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
        CallHistoryScreen(),
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.xBg,
    body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: context.xCard, shape: BoxShape.circle,
            border: Border.all(
                color: context.xPrimary.withValues(alpha: 0.3))),
          child: Icon(Icons.schedule_outlined,
              color: context.xPrimary, size: 56)),
        SizedBox(height: 24),
        Text('Call Schedule',
            style: TextStyle(color: context.xText,
                fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        Text('Schedule calls with your contacts',
            style: TextStyle(color: context.xMuted, fontSize: 14),
            textAlign: TextAlign.center),
        SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () {},
          icon: Icon(Icons.add),
          label: Text('Schedule a Call',
              style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: XameColors.primary,
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
  _ConferenceTab();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.xBg,
    body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: context.xCard, shape: BoxShape.circle,
            border: Border.all(
                color: context.xPrimary.withValues(alpha: 0.3))),
          child: Icon(Icons.groups_rounded,
              color: context.xPrimary, size: 56)),
        SizedBox(height: 24),
        Text('Conference Call',
            style: TextStyle(color: context.xText,
                fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        Text('Start a call with multiple contacts at once',
            style: TextStyle(color: context.xMuted, fontSize: 14),
            textAlign: TextAlign.center),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add_call),
          label: const Text('Start Conference',
              style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: XameColors.primary,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        ),
      ],
    )),
  );
}
