import 'package:flutter/material.dart';

/// Temă sportivă dark: gazon + roșu/albastru pentru echipe (specificație 5 / 4.1).
abstract final class SimfTheme {
  static const Color pitchGreen = Color(0xFF1B4332);
  static const Color pitchGreenLight = Color(0xFF2D6A4F);
  static const Color teamRed = Color(0xFFE63946);
  static const Color teamBlue = Color(0xFF457B9D);
  static const Color surface = Color(0xFF0D1117);

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: pitchGreenLight,
        brightness: Brightness.dark,
        surface: surface,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: pitchGreenLight,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: pitchGreen,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );
  }
}
