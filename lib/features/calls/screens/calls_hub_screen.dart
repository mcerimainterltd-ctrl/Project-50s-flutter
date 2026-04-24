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
      body: IndexedStack(index: _tab, children: const [
        CallHistoryScreen(),
        _ConferenceTab(),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: XameColors.darkSurface,
          border: Border(top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06)))),
        child: SafeArea(
          child: Row(children: [
            _NavItem(
              icon: Icons.history_rounded,
              label: 'Call Schedule',
              selected: _tab == 0,
              onTap: () => setState(() => _tab = 0)),
            _NavItem(
              icon: Icons.groups_rounded,
              label: 'Conference',
              selected: _tab == 1,
              onTap: () => setState(() => _tab = 1)),
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

// ── Conference Tab ────────────────────────────────────────────────────────────
class _ConferenceTab extends StatelessWidget {
  const _ConferenceTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: XameColors.darkBg,
      appBar: AppBar(
        backgroundColor: XameColors.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white70, size: 18),
          onPressed: () => Navigator.pop(context)),
        title: const Text('Conference Call',
            style: TextStyle(color: Colors.white,
                fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: XameColors.darkCard,
              shape: BoxShape.circle,
              border: Border.all(
                  color: XameColors.primary.withValues(alpha: 0.3))),
            child: Icon(Icons.groups_rounded,
                color: XameColors.primary, size: 56)),
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
              backgroundColor: XameColors.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(
                  horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
          ),
        ],
      )),
    );
  }
}
