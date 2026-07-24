/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     WiyaMusic is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     WiyaMusic is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about WiyaMusic, including how to contribute,
 *     please visit: https://github.com/Wiyam12/wiyamusic
 */

import 'dart:ui';

import 'package:flutter/material.dart';

/// WiyaMusic visual language: Modern Dark Glassmorphism.
///
/// Style contract:
/// - theme: Modern Dark Glassmorphism
/// - designStyle: Premium Music Streaming
/// - uiStyle: Minimal, Clean, Rounded
/// - iconStyle: Neon Gradient
/// - cornerRadius: 28
/// - shadow: Soft Glow
/// - blur: 30
abstract final class WiyaDesign {
  static const double cornerRadius = 28;
  static const double cornerRadiusMedium = 20;
  static const double cornerRadiusSmall = 14;
  static const double blurSigma = 30;

  static const Color background = Color(0xFF050B1B);
  static const Color surface = Color(0xFF0F172A);
  static const Color surfaceLow = Color(0xFF121C31);
  static const Color surfaceContainer = Color(0xFF16233A);
  static const Color surfaceHigh = Color(0xFF1A2A45);
  static const Color surfaceHighest = Color(0xFF243552);
  static const Color primary = Color(0xFF38B2F6);
  static const Color primaryBright = Color(0xFF60A5FA);
  static const Color primaryDeep = Color(0xFF2563EB);
  static const Color onPrimary = Color(0xFF04101F);
  static const Color onSurface = Color(0xFFF1F5FF);
  static const Color onSurfaceVariant = Color(0xFFA8B8D8);
  static const Color outline = Color(0xFF3A4F73);
  static const Color outlineVariant = Color(0xFF2A3B58);
  static const Color error = Color(0xFFFF6B8A);

  static BorderRadius get borderRadius => BorderRadius.circular(cornerRadius);

  static BorderRadius get borderRadiusMedium =>
      BorderRadius.circular(cornerRadiusMedium);

  static List<BoxShadow> softGlow({
    Color? color,
    double blur = 24,
    double opacity = 0.28,
  }) {
    final glow = (color ?? primary).withValues(alpha: opacity);
    return [
      BoxShadow(color: glow, blurRadius: blur, offset: const Offset(0, 8)),
      BoxShadow(
        color: glow.withValues(alpha: opacity * 0.45),
        blurRadius: blur * 0.45,
        spreadRadius: -2,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static BoxDecoration glassSurface({
    required ColorScheme colorScheme,
    double radius = cornerRadius,
    double fillOpacity = 0.72,
    bool withGlow = false,
  }) {
    return BoxDecoration(
      color: colorScheme.surfaceContainerHigh.withValues(alpha: fillOpacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: primaryBright.withValues(alpha: 0.22)),
      boxShadow: withGlow
          ? softGlow(color: colorScheme.primary)
          : softGlow(color: background, blur: 18, opacity: 0.45),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          colorScheme.surfaceContainerHigh.withValues(alpha: fillOpacity),
        ],
      ),
    );
  }

  static ImageFilter get glassBlur =>
      ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma);

  /// Brand ColorScheme for dark (glass) mode.
  static ColorScheme get darkColorScheme => const ColorScheme(
    brightness: Brightness.dark,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryDeep,
    onPrimaryContainer: onSurface,
    secondary: primaryBright,
    onSecondary: onPrimary,
    secondaryContainer: Color(0xFF1F3C5F),
    onSecondaryContainer: onSurface,
    tertiary: Color(0xFF7DD3FC),
    onTertiary: onPrimary,
    tertiaryContainer: Color(0xFF164E75),
    onTertiaryContainer: onSurface,
    error: error,
    onError: onPrimary,
    errorContainer: Color(0xFF5A1D2E),
    onErrorContainer: Color(0xFFFFD9E0),
    surface: surface,
    onSurface: onSurface,
    surfaceContainerLowest: background,
    surfaceContainerLow: surfaceLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceHigh,
    surfaceContainerHighest: surfaceHighest,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outlineVariant,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: onSurface,
    onInverseSurface: background,
    inversePrimary: primaryDeep,
  );

  /// Softer light counterpart so system light mode stays coherent.
  static ColorScheme get lightColorScheme =>
      ColorScheme.fromSeed(seedColor: primary);
}
