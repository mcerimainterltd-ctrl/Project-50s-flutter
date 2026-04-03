import 'package:flutter/material.dart';

class XameColors {
  static const primary     = Color(0xFF00D4FF);
  static const secondary   = Color(0xFF7B2FFF);
  static const accent      = Color(0xFF00FF88);
  static const danger      = Color(0xFFFF3B5C);
  static const darkBg      = Color(0xFF0A0A0F);
  static const darkSurface = Color(0xFF141420);
  static const darkCard    = Color(0xFF1E1E2E);
  static const lightBg     = Color(0xFFF5F5FA);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary:   XameColors.primary,
      secondary: XameColors.secondary,
      surface:   XameColors.darkSurface,
      error:     XameColors.danger,
    ),
    scaffoldBackgroundColor: XameColors.darkBg,
    cardColor: XameColors.darkCard,
    appBarTheme: const AppBarTheme(
      backgroundColor: XameColors.darkBg,
      elevation: 0,
    ),
  );
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary:   XameColors.primary,
      secondary: XameColors.secondary,
      error:     XameColors.danger,
    ),
  );
}
