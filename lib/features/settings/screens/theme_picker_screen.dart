import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';

class ThemePickerScreen extends ConsumerWidget {
  const ThemePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: current.bg,
      appBar: AppBar(
        backgroundColor: current.surface,
        title: Text('Appearance',
          style: TextStyle(color: current.text, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: current.text, size: 18),
          onPressed: () => Navigator.pop(context)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // Section title
          Text('Theme',
            style: TextStyle(color: current.textSecondary, fontSize: 12,
                fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          const SizedBox(height: 14),

          // Theme grid
          GridView.builder(
            shrinkWrap:  true,
            physics:     const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:  2,
              childAspectRatio: 1.3,
              crossAxisSpacing: 12,
              mainAxisSpacing:  12,
            ),
            itemCount:  kXameThemes.length,
            itemBuilder: (_, i) {
              final theme    = kXameThemes[i];
              final isActive = current.id == theme.id;
              return GestureDetector(
                onTap: () => ref.read(themeProvider.notifier).setTheme(theme),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isActive
                          ? theme.primary
                          : context.xText.withValues(alpha: 0.08),
                      width: isActive ? 2.5 : 1,
                    ),
                    boxShadow: isActive ? [
                      BoxShadow(color: theme.primary.withValues(alpha: 0.3),
                          blurRadius: 12, spreadRadius: 2),
                    ] : [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Column(children: [
                      // Preview
                      Expanded(
                        child: Stack(fit: StackFit.expand, children: [
                          // Background gradient
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: theme.gradientColors,
                              ),
                            ),
                          ),
                          // Mini chat preview
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Received bubble
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    width: 55, height: 10,
                                    decoration: BoxDecoration(
                                      color: theme.bubbleReceived
                                          .withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                // Sent bubble
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    width: 45, height: 10,
                                    decoration: BoxDecoration(
                                      color: theme.bubbleSent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Active checkmark
                          if (isActive)
                            Positioned(
                              top: 8, right: 8,
                              child: Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  color: theme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check,
                                    color: context.xText, size: 14),
                              ),
                            ),
                        ]),
                      ),
                      // Label
                      Container(
                        color: theme.surface,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(children: [
                          Text(theme.emoji, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(theme.name,
                            style: TextStyle(
                              color: isActive ? theme.primary : theme.text,
                              fontSize: 12,
                              fontWeight: isActive
                                  ? FontWeight.w700 : FontWeight.w500),
                            overflow: TextOverflow.ellipsis)),
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: theme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 32),

          // Light/Dark badge row
          Text('Mode',
            style: TextStyle(color: current.textSecondary, fontSize: 12,
                fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          const SizedBox(height: 12),
          Row(children: [
            _ModeBadge(label: '☀️  Light themes',
                count: kXameThemes.where((t) => !t.isDark).length,
                color: current.accent),
            const SizedBox(width: 12),
            _ModeBadge(label: '🌑  Dark themes',
                count: kXameThemes.where((t) => t.isDark).length,
                color: current.primary),
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final String label;
  final int    count;
  final Color  color;
  const _ModeBadge({required this.label, required this.count,
      required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Text(label, style: TextStyle(color: color, fontSize: 12,
            fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('$count', style: TextStyle(color: color, fontSize: 16,
            fontWeight: FontWeight.w800)),
      ]),
    ),
  );
}
