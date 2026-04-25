import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ── Theme model ───────────────────────────────────────────────────────────────
class XameTheme {
  final String   id;
  final String   name;
  final String   emoji;
  final bool     isDark;
  final Color    bg;
  final Color    surface;
  final Color    card;
  final Color    primary;
  final Color    secondary;
  final Color    accent;
  final Color    danger;
  final Color    text;
  final Color    textSecondary;
  final Color    bubbleSent;
  final Color    bubbleReceived;
  final Color    bubbleSentText;
  final Color    bubbleRecvText;
  final List<Color> gradientColors; // for theme preview card

  const XameTheme({
    required this.id,           required this.name,
    required this.emoji,        required this.isDark,
    required this.bg,           required this.surface,
    required this.card,         required this.primary,
    required this.secondary,    required this.accent,
    required this.danger,       required this.text,
    required this.textSecondary,
    required this.bubbleSent,   required this.bubbleReceived,
    required this.bubbleSentText, required this.bubbleRecvText,
    required this.gradientColors,
  });

  ThemeData toThemeData() => ThemeData(
    useMaterial3:           true,
    brightness:             isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: bg,
    cardColor:              card,
    colorScheme: isDark
        ? ColorScheme.dark(
            primary:   primary,
            secondary: secondary,
            surface:   surface,
            error:     danger,
            onPrimary: bubbleSentText,
            onSurface: text,
          )
        : ColorScheme.light(
            primary:   primary,
            secondary: secondary,
            surface:   surface,
            error:     danger,
            onPrimary: bubbleSentText,
            onSurface: text,
          ),
    appBarTheme: AppBarTheme(
      backgroundColor:  surface,
      foregroundColor:  text,
      elevation:        0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled:    true,
      fillColor: card,
    ),
    switchTheme: SwitchThemeData(
      thumbColor:  WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : Colors.grey),
      trackColor:  WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.3)),
    ),
  );
}

// ── 10 Themes ─────────────────────────────────────────────────────────────────
const kXameThemes = <XameTheme>[

  // 1. Obsidian (default dark)
  XameTheme(
    id: 'obsidian', name: 'Obsidian', emoji: '🌑', isDark: true,
    bg:              Color(0xFF0A0A0F),
    surface:         Color(0xFF141420),
    card:            Color(0xFF1E1E2E),
    primary:         Color(0xFF00D4FF),
    secondary:       Color(0xFF7B2FFF),
    accent:          Color(0xFF00FF88),
    danger:          Color(0xFFFF3B5C),
    text:            Color(0xFFFFFFFF),
    textSecondary:   Color(0xFF8899A6),
    bubbleSent:      Color(0xFF1A4A6E),
    bubbleReceived:  Color(0xFF1E1E2E),
    bubbleSentText:  Color(0xFFFFFFFF),
    bubbleRecvText:  Color(0xFFFFFFFF),
    gradientColors:  [Color(0xFF0A0A0F), Color(0xFF1E1E2E), Color(0xFF00D4FF)],
  ),

  // 2. Midnight (deep navy)
  XameTheme(
    id: 'midnight', name: 'Midnight', emoji: '🌊', isDark: true,
    bg:              Color(0xFF070D1A),
    surface:         Color(0xFF0D1B2E),
    card:            Color(0xFF112440),
    primary:         Color(0xFF4F8EF7),
    secondary:       Color(0xFF8E54E9),
    accent:          Color(0xFF00C87E),
    danger:          Color(0xFFE8394A),
    text:            Color(0xFFE8EDF5),
    textSecondary:   Color(0xFF7A9BC4),
    bubbleSent:      Color(0xFF1A3A6E),
    bubbleReceived:  Color(0xFF0D1B2E),
    bubbleSentText:  Color(0xFFE8EDF5),
    bubbleRecvText:  Color(0xFFE8EDF5),
    gradientColors:  [Color(0xFF070D1A), Color(0xFF0D1B2E), Color(0xFF4F8EF7)],
  ),

  // 3. Emerald Forest
  XameTheme(
    id: 'forest', name: 'Emerald', emoji: '🌿', isDark: true,
    bg:              Color(0xFF0A140D),
    surface:         Color(0xFF111E14),
    card:            Color(0xFF172B1A),
    primary:         Color(0xFF2ECC71),
    secondary:       Color(0xFF3AAFCC),
    accent:          Color(0xFFF0B429),
    danger:          Color(0xFFE84040),
    text:            Color(0xFFE0EDE2),
    textSecondary:   Color(0xFF7AAA82),
    bubbleSent:      Color(0xFF1A4A22),
    bubbleReceived:  Color(0xFF111E14),
    bubbleSentText:  Color(0xFFE0EDE2),
    bubbleRecvText:  Color(0xFFE0EDE2),
    gradientColors:  [Color(0xFF0A140D), Color(0xFF111E14), Color(0xFF2ECC71)],
  ),

  // 4. Crimson Dusk
  XameTheme(
    id: 'crimson', name: 'Crimson', emoji: '🔴', isDark: true,
    bg:              Color(0xFF110A0A),
    surface:         Color(0xFF1E1010),
    card:            Color(0xFF2A1515),
    primary:         Color(0xFFE53935),
    secondary:       Color(0xFFFF6D00),
    accent:          Color(0xFFFFD600),
    danger:          Color(0xFFFF1744),
    text:            Color(0xFFFFF3F3),
    textSecondary:   Color(0xFFBB8888),
    bubbleSent:      Color(0xFF6B1A1A),
    bubbleReceived:  Color(0xFF1E1010),
    bubbleSentText:  Color(0xFFFFF3F3),
    bubbleRecvText:  Color(0xFFFFF3F3),
    gradientColors:  [Color(0xFF110A0A), Color(0xFF2A1515), Color(0xFFE53935)],
  ),

  // 5. Violet Nebula
  XameTheme(
    id: 'nebula', name: 'Nebula', emoji: '🌌', isDark: true,
    bg:              Color(0xFF0D0A1A),
    surface:         Color(0xFF150F2A),
    card:            Color(0xFF1E1540),
    primary:         Color(0xFF9C27B0),
    secondary:       Color(0xFF673AB7),
    accent:          Color(0xFF00BCD4),
    danger:          Color(0xFFFF4081),
    text:            Color(0xFFEDE7FF),
    textSecondary:   Color(0xFF9E8AC4),
    bubbleSent:      Color(0xFF4A1A6E),
    bubbleReceived:  Color(0xFF150F2A),
    bubbleSentText:  Color(0xFFEDE7FF),
    bubbleRecvText:  Color(0xFFEDE7FF),
    gradientColors:  [Color(0xFF0D0A1A), Color(0xFF1E1540), Color(0xFF9C27B0)],
  ),

  // 6. Sahara Gold
  XameTheme(
    id: 'sahara', name: 'Sahara', emoji: '🏜️', isDark: true,
    bg:              Color(0xFF140E00),
    surface:         Color(0xFF221800),
    card:            Color(0xFF2E2200),
    primary:         Color(0xFFFFB300),
    secondary:       Color(0xFFFF6F00),
    accent:          Color(0xFF76FF03),
    danger:          Color(0xFFFF3D00),
    text:            Color(0xFFFFF8E1),
    textSecondary:   Color(0xFFBCA85A),
    bubbleSent:      Color(0xFF5C3D00),
    bubbleReceived:  Color(0xFF221800),
    bubbleSentText:  Color(0xFFFFF8E1),
    bubbleRecvText:  Color(0xFFFFF8E1),
    gradientColors:  [Color(0xFF140E00), Color(0xFF2E2200), Color(0xFFFFB300)],
  ),

  // 7. Arctic Ice
  XameTheme(
    id: 'arctic', name: 'Arctic', emoji: '❄️', isDark: false,
    bg:              Color(0xFFF0F8FF),
    surface:         Color(0xFFE1F0FA),
    card:            Color(0xFFCDE4F5),
    primary:         Color(0xFF0288D1),
    secondary:       Color(0xFF26C6DA),
    accent:          Color(0xFF00897B),
    danger:          Color(0xFFD32F2F),
    text:            Color(0xFF0D2137),
    textSecondary:   Color(0xFF4A7A9B),
    bubbleSent:      Color(0xFF0288D1),
    bubbleReceived:  Color(0xFFCDE4F5),
    bubbleSentText:  Color(0xFFFFFFFF),
    bubbleRecvText:  Color(0xFF0D2137),
    gradientColors:  [Color(0xFFF0F8FF), Color(0xFFCDE4F5), Color(0xFF0288D1)],
  ),

  // 8. Cherry Blossom
  XameTheme(
    id: 'blossom', name: 'Blossom', emoji: '🌸', isDark: false,
    bg:              Color(0xFFFFF5F7),
    surface:         Color(0xFFFFE4EC),
    card:            Color(0xFFFFD0E0),
    primary:         Color(0xFFE91E8C),
    secondary:       Color(0xFFAD1457),
    accent:          Color(0xFFFF6D00),
    danger:          Color(0xFFB71C1C),
    text:            Color(0xFF2D0A1A),
    textSecondary:   Color(0xFF8C4A62),
    bubbleSent:      Color(0xFFE91E8C),
    bubbleReceived:  Color(0xFFFFD0E0),
    bubbleSentText:  Color(0xFFFFFFFF),
    bubbleRecvText:  Color(0xFF2D0A1A),
    gradientColors:  [Color(0xFFFFF5F7), Color(0xFFFFD0E0), Color(0xFFE91E8C)],
  ),

  // 9. Slate (minimal light)
  XameTheme(
    id: 'slate', name: 'Slate', emoji: '☁️', isDark: false,
    bg:              Color(0xFFFFFFFF),
    surface:         Color(0xFFF7F9FA),
    card:            Color(0xFFEFF3F4),
    primary:         Color(0xFF0084FF),
    secondary:       Color(0xFF1D9BF0),
    accent:          Color(0xFF00BA7C),
    danger:          Color(0xFFF4212E),
    text:            Color(0xFF0F1419),
    textSecondary:   Color(0xFF536471),
    bubbleSent:      Color(0xFF0084FF),
    bubbleReceived:  Color(0xFFEFF3F4),
    bubbleSentText:  Color(0xFFFFFFFF),
    bubbleRecvText:  Color(0xFF0F1419),
    gradientColors:  [Color(0xFFFFFFFF), Color(0xFFEFF3F4), Color(0xFF0084FF)],
  ),

  // 10. Volcano (high contrast dark)
  XameTheme(
    id: 'volcano', name: 'Volcano', emoji: '🌋', isDark: true,
    bg:              Color(0xFF080808),
    surface:         Color(0xFF111111),
    card:            Color(0xFF1A1A1A),
    primary:         Color(0xFFFF6B00),
    secondary:       Color(0xFFFF3D00),
    accent:          Color(0xFFFFD600),
    danger:          Color(0xFFFF1744),
    text:            Color(0xFFFFFFFF),
    textSecondary:   Color(0xFF999999),
    bubbleSent:      Color(0xFF7A2D00),
    bubbleReceived:  Color(0xFF1A1A1A),
    bubbleSentText:  Color(0xFFFFFFFF),
    bubbleRecvText:  Color(0xFFFFFFFF),
    gradientColors:  [Color(0xFF080808), Color(0xFF1A1A1A), Color(0xFFFF6B00)],
  ),
];

// ── Provider ──────────────────────────────────────────────────────────────────
final themeProvider = StateNotifierProvider<ThemeNotifier, XameTheme>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<XameTheme> {
  static const _boxKey   = 'xame_prefs';
  static const _themeKey = 'theme_id';

  ThemeNotifier() : super(kXameThemes.first) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox(_boxKey);
    final id  = box.get(_themeKey, defaultValue: 'obsidian') as String;
    final t   = kXameThemes.firstWhere(
        (t) => t.id == id, orElse: () => kXameThemes.first);
    state = t;
  }

  Future<void> setTheme(XameTheme theme) async {
    state = theme;
    final box = await Hive.openBox(_boxKey);
    await box.put(_themeKey, theme.id);
  }
}

// ── XameColors — dynamic, reads from active theme ────────────────────────────
// Usage: XameColors.of(context).primary  OR  XameColors.primary (fallback)
class XameColors {
  // ── Static fallbacks (used where context unavailable) ────────────────────
  static const primary     = Color(0xFF00D4FF);
  static const secondary   = Color(0xFF7B2FFF);
  static const accent      = Color(0xFF00FF88);
  static const danger      = Color(0xFFFF3B5C);
  static const darkBg      = Color(0xFF0A0A0F);
  static const darkSurface = Color(0xFF141420);
  static const darkCard    = Color(0xFF1E1E2E);
  static const lightBg     = Color(0xFFF5F5FA);

  // ── Dynamic accessors — reads active theme ────────────────────────────────
  static XameTheme of(BuildContext context) {
    // Walk up the widget tree to find ProviderScope
    try {
      return ProviderScope.containerOf(context).read(themeProvider);
    } catch (_) {
      return kXameThemes.first;
    }
  }
}

// ── Theme extension for convenient BuildContext access ────────────────────────
extension XameThemeContext on BuildContext {
  XameTheme get xTheme {
    try {
      return ProviderScope.containerOf(this).read(themeProvider);
    } catch (_) {
      return kXameThemes.first;
    }
  }
  Color get xBg      => xTheme.bg;
  Color get xCard    => xTheme.card;
  Color get xSurface => xTheme.surface;
  Color get xPrimary => xTheme.primary;
  Color get xAccent  => xTheme.accent;
  Color get xDanger  => xTheme.danger;
  Color get xText    => xTheme.text;
  Color get xMuted   => xTheme.textSecondary;
}

class AppTheme {
  static ThemeData get dark => kXameThemes.first.toThemeData();
  static ThemeData get light => kXameThemes
      .firstWhere((t) => !t.isDark, orElse: () => kXameThemes.first)
      .toThemeData();
}
