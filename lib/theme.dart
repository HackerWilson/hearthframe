import 'package:flutter/material.dart';

/// Warm, low-contrast palette for a device that stays on all day.
abstract final class HearthPalette {
  static const background = Color(0xFF0A0F0E);
  static const panel = Color(0xFF121917);
  static const card = Color(0xFF17201D);
  static const primary = Color(0xFF9BD4B8);
  static const accent = Color(0xFFE7C08D);
  static const text = Color(0xFFF1F5F2);
}

ThemeData buildHearthTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HearthPalette.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: HearthPalette.primary,
    secondary: HearthPalette.accent,
    surface: HearthPalette.panel,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: HearthPalette.background,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}
