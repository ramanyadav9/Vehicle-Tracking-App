import 'package:flutter/material.dart';

/// Global theme state: true = dark, false = light
final themeNotifier = ValueNotifier<bool>(true);

bool get isDark => themeNotifier.value;

class AppColors {
  AppColors._();

  // Backgrounds
  static Color get bg => isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F5F5);
  static Color get surface => isDark ? const Color(0xFF0D1117) : const Color(0xFFFFFFFF);
  static Color get surfaceOverlay => isDark
      ? const Color(0xFF161B22)
      : const Color(0xFFFFFFFF);

  // Accent — bright teal on dark, deeper teal on light for contrast
  static Color get accent => isDark ? const Color(0xFF00E5CC) : const Color(0xFF00897B);
  /// Hex string for MapLibre native circle color
  static String get accentHex => isDark ? '#00E5CC' : '#00897B';
  static const Color warning = Color(0xFFFFB800);

  // Map glow opacities — stronger on light so it's visible on white tiles
  static double get mapGlowAlpha => isDark ? 0.15 : 0.35;
  static double get mapCircleOpacity => isDark ? 0.10 : 0.28;

  // Text
  static Color get textPrimary => isDark ? Colors.white : const Color(0xFF1A1A2E);
  static Color get textSecondary => isDark
      ? Colors.white.withValues(alpha: 0.45)
      : const Color(0xFF1A1A2E).withValues(alpha: 0.6);
  static Color get textFaint => isDark
      ? Colors.white.withValues(alpha: 0.35)
      : const Color(0xFF1A1A2E).withValues(alpha: 0.5);
  static Color get textSubtle => isDark
      ? Colors.white.withValues(alpha: 0.6)
      : const Color(0xFF1A1A2E).withValues(alpha: 0.65);

  // Borders & shadows
  static Color get border => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.12);
  static Color get shadow => isDark
      ? Colors.black.withValues(alpha: 0.4)
      : Colors.black.withValues(alpha: 0.18);
  static Color get shadowHeavy => isDark
      ? Colors.black.withValues(alpha: 0.5)
      : Colors.black.withValues(alpha: 0.22);

  // Translucent surface for overlays (buttons, cards on map)
  static Color get surfaceTranslucent => isDark
      ? const Color(0xFF0D1117).withValues(alpha: 0.92)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.95);
  static Color get surfaceHeavy => isDark
      ? const Color(0xFF0D1117).withValues(alpha: 0.96)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.98);

  // Bus icon fill (center circle behind bus drawing)
  // Light mode uses warm off-white so the icon doesn't blend into light map tiles
  static Color get busIconFill => isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F0F0);

  // Divider / subtle bg — used for timeline lines in route sheet
  static Color get divider => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.15);

  // Handle bar color
  static Color get handleBar => isDark
      ? Colors.white.withValues(alpha: 0.15)
      : Colors.black.withValues(alpha: 0.15);
}
