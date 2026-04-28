import 'package:flutter/material.dart';

/// Temă sportivă dark: gazon + roșu/albastru pentru echipe (specificație 5 / 4.1).
///
/// Evită `surfaceTint` implicit M3 (altfel AppBar/cardurile capătă un „wash” verde).
abstract final class SimfTheme {
  static const Color pitchGreen = Color(0xFF1B4332);
  static const Color pitchGreenLight = Color(0xFF2D6A4F);
  static const Color teamRed = Color(0xFFE63946);
  static const Color teamBlue = Color(0xFF457B9D);
  static const Color surface = Color(0xFF0D1117);
  static const Color surface2 = Color(0xFF121A22);
  static const Color card = Color(0xFF101822);
  static const Color outline = Color(0xFF2A3746);
  static const Color amber = Color(0xFFFFC857);

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: pitchGreenLight,
      brightness: Brightness.dark,
    ).copyWith(
      surface: surface,
      surfaceContainerLow: surface2,
      surfaceContainer: card,
      surfaceContainerHigh: const Color(0xFF151D26),
      surfaceContainerHighest: const Color(0xFF18212C),
      primary: pitchGreenLight,
      onPrimary: Colors.white,
      secondary: teamBlue,
      onSecondary: Colors.white,
      tertiary: teamRed,
      onTertiary: Colors.white,
      outline: outline,
      outlineVariant: outline.withValues(alpha: 0.65),
      surfaceTint: Colors.transparent,
    );

    final text = base.textTheme.apply(
      bodyColor: Colors.white.withValues(alpha: 0.92),
      displayColor: Colors.white,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
        ),
        bodyLarge: text.bodyLarge?.copyWith(
          height: 1.35,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          height: 1.3,
          color: Colors.white.withValues(alpha: 0.85),
        ),
        labelLarge: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outline.withValues(alpha: 0.85), width: 0.7),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: outline.withValues(alpha: 0.75),
        thickness: 0.6,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outline.withValues(alpha: 0.9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outline.withValues(alpha: 0.9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: pitchGreenLight, width: 1.4),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: Colors.white.withValues(alpha: 0.72),
        textColor: Colors.white.withValues(alpha: 0.95),
        titleTextStyle: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.62),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: pitchGreenLight,
        foregroundColor: Colors.white,
        elevation: 2,
        highlightElevation: 4,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 44),
          foregroundColor: Colors.white.withValues(alpha: 0.9),
          side: BorderSide(color: outline.withValues(alpha: 0.95)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: pitchGreenLight.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: outline.withValues(alpha: 0.8)),
        ),
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        contentTextStyle: text.bodyMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.88),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: pitchGreen,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: pitchGreenLight,
        linearTrackColor: surface2,
        circularTrackColor: surface2,
      ),
      iconTheme: IconThemeData(color: Colors.white.withValues(alpha: 0.85)),
      popupMenuTheme: PopupMenuThemeData(
        color: surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: outline.withValues(alpha: 0.7)),
        ),
      ),
    );
  }

  /// Înălțime comună pentru butoane acțiune pe lățime completă (setup meci, etc.).
  static const double wideActionButtonHeight = 50;

  static final BorderRadius _wideActionButtonRadius = BorderRadius.circular(14);

  /// [FilledButton] full-lățime: aceeași înălțime și colțuri ca la tema globală.
  static ButtonStyle wideFilledButton(BuildContext context) {
    final t = FilledButtonTheme.of(context).style;
    return (t ?? const ButtonStyle()).merge(
      FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, wideActionButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: _wideActionButtonRadius),
      ),
    );
  }

  /// [OutlinedButton] full-lățime: aliniat vizual cu [wideFilledButton].
  static ButtonStyle wideOutlinedButton(BuildContext context) {
    final t = OutlinedButtonTheme.of(context).style;
    return (t ?? const ButtonStyle()).merge(
      OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, wideActionButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: _wideActionButtonRadius),
      ),
    );
  }
}
