import 'package:flutter/material.dart';

/// Tokens de cor do design system hoink. (DESIGN.md + configuração Tailwind dos protótipos).
abstract final class HoinkColors {
  // Paleta oficial da marca
  static const pine = Color(0xFF103E37); // primary-container
  static const ivory = Color(0xFFFFF9F1);
  static const pigPink = Color(0xFFF3A9B8);
  static const mint = Color(0xFFB9E9CF);
  static const charcoal = Color(0xFF1D2925);

  // Tokens de superfície (Material 3 gerado pelo Stitch)
  static const primary = Color(0xFF002722);
  static const onPrimaryContainer = Color(0xFF7DA9A0);
  static const primaryFixed = Color(0xFFBEECE1);
  static const primaryFixedDim = Color(0xFFA2D0C6);
  static const surfaceTint = Color(0xFF3B665E);
  static const background = Color(0xFFEFFDF6);
  static const surface = Color(0xFFEFFDF6);
  static const surfaceLowest = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFE9F7F0);
  static const surfaceContainer = Color(0xFFE3F1EA);
  static const surfaceHigh = Color(0xFFDEEBE5);
  static const surfaceHighest = Color(0xFFD8E6DF);
  static const onSurface = Color(0xFF121E1A);
  static const onSurfaceVariant = Color(0xFF404846);
  static const outline = Color(0xFF717976);
  static const outlineVariant = Color(0xFFC0C8C5);
  static const tertiary = Color(0xFF40121F);
  static const tertiaryContainer = Color(0xFF5A2734);
  static const tertiaryFixed = Color(0xFFFFD9DF);
  static const tertiaryFixedDim = Color(0xFFFDB2C1);
  static const onTertiaryFixed = Color(0xFF370B19);
  static const onTertiaryFixedVariant = Color(0xFF6C3643);
  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);
  static const stroke = Color(0x14103E37); // rgba(16,62,55,0.08)
}

/// Escala tipográfica (Sora) conforme DESIGN.md.
abstract final class HoinkText {
  static const _f = 'Sora';
  static const _tnum = [FontFeature.tabularFigures()];

  static const displayHero = TextStyle(
    fontFamily: _f,
    fontSize: 40,
    height: 48 / 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
  );
  static const displayHeroMobile = TextStyle(
    fontFamily: _f,
    fontSize: 30,
    height: 36 / 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );
  static const headlineLg = TextStyle(
    fontFamily: _f,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.56,
  );
  static const headlineLgMobile = TextStyle(
    fontFamily: _f,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.22,
  );
  static const headlineMd = TextStyle(
    fontFamily: _f,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const headlineSm = TextStyle(fontFamily: _f, fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600);
  static const currencyDisplay = TextStyle(
    fontFamily: _f,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.64,
    fontFeatures: _tnum,
  );
  static const currencyDisplayMobile = TextStyle(
    fontFamily: _f,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.24,
    fontFeatures: _tnum,
  );
  static const bodyLg = TextStyle(fontFamily: _f, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400);
  static const bodyMd = TextStyle(fontFamily: _f, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400);
  static const bodySm = TextStyle(
    fontFamily: _f,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.12,
  );
  static const labelMd = TextStyle(
    fontFamily: _f,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.13,
  );
  static const labelSm = TextStyle(
    fontFamily: _f,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.44,
  );
  static const money = TextStyle(fontFamily: _f, fontFeatures: _tnum);
}

abstract final class HoinkRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

abstract final class HoinkShadows {
  /// Nível 1 — superfícies elevadas (cartões).
  static const level1 = [BoxShadow(color: Color(0x0A103E37), blurRadius: 16, offset: Offset(0, 4), spreadRadius: -2)];

  /// Nível 2 — flutuantes e menus.
  static const level2 = [BoxShadow(color: Color(0x14103E37), blurRadius: 32, offset: Offset(0, 12), spreadRadius: -4)];
}

ThemeData buildHoinkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: HoinkColors.pine,
    onPrimary: Colors.white,
    primaryContainer: HoinkColors.pine,
    onPrimaryContainer: HoinkColors.onPrimaryContainer,
    secondary: Color(0xFF615E58),
    onSecondary: Colors.white,
    tertiary: HoinkColors.tertiary,
    onTertiary: Colors.white,
    tertiaryContainer: HoinkColors.tertiaryFixed,
    onTertiaryContainer: HoinkColors.onTertiaryFixed,
    error: HoinkColors.error,
    onError: Colors.white,
    errorContainer: HoinkColors.errorContainer,
    onErrorContainer: HoinkColors.onErrorContainer,
    surface: HoinkColors.surface,
    onSurface: HoinkColors.onSurface,
    onSurfaceVariant: HoinkColors.onSurfaceVariant,
    surfaceContainerLowest: HoinkColors.surfaceLowest,
    surfaceContainerLow: HoinkColors.surfaceLow,
    surfaceContainer: HoinkColors.surfaceContainer,
    surfaceContainerHigh: HoinkColors.surfaceHigh,
    surfaceContainerHighest: HoinkColors.surfaceHighest,
    outline: HoinkColors.outline,
    outlineVariant: HoinkColors.outlineVariant,
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(HoinkRadius.md),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Sora',
    scaffoldBackgroundColor: HoinkColors.background,
    textTheme: const TextTheme(
      displayLarge: HoinkText.displayHero,
      headlineLarge: HoinkText.headlineLg,
      headlineMedium: HoinkText.headlineMd,
      headlineSmall: HoinkText.headlineSm,
      titleLarge: HoinkText.headlineMd,
      titleMedium: HoinkText.headlineSm,
      titleSmall: HoinkText.labelMd,
      bodyLarge: HoinkText.bodyLg,
      bodyMedium: HoinkText.bodyMd,
      bodySmall: HoinkText.bodySm,
      labelLarge: HoinkText.labelMd,
      labelMedium: HoinkText.labelMd,
      labelSmall: HoinkText.labelSm,
    ).apply(bodyColor: HoinkColors.onSurface, displayColor: HoinkColors.primary),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HoinkColors.surfaceLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: HoinkColors.pine, width: 1.5)),
      errorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: HoinkColors.error)),
      hintStyle: HoinkText.bodyMd.copyWith(color: HoinkColors.outline),
      labelStyle: HoinkText.bodyMd.copyWith(color: HoinkColors.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HoinkColors.pine,
        foregroundColor: HoinkColors.ivory,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: const StadiumBorder(),
        textStyle: HoinkText.labelMd.copyWith(fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: HoinkColors.pine,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Color(0x29103E37)),
        shape: const StadiumBorder(),
        textStyle: HoinkText.labelMd.copyWith(fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: HoinkColors.pine, textStyle: HoinkText.labelMd),
    ),
    dividerTheme: const DividerThemeData(color: HoinkColors.stroke, space: 1, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: HoinkColors.charcoal,
      contentTextStyle: HoinkText.bodyMd.copyWith(color: HoinkColors.ivory),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HoinkRadius.md)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: HoinkColors.surfaceLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HoinkRadius.xl)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: HoinkColors.surfaceLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HoinkRadius.xl))),
    ),
  );
}
