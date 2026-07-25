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

import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wiyamusic/constants/app_constants.dart';
import 'package:wiyamusic/services/settings_manager.dart';
import 'package:wiyamusic/theme/design_tokens.dart';
import 'package:wiyamusic/theme/dynamic_color_compat.dart';

ThemeMode themeMode = getThemeMode(themeModeSetting);
Brightness brightness = getBrightnessFromThemeMode(themeMode);

PageTransitionsBuilder transitionsBuilder =
    Platform.isAndroid && predictiveBack.value
    ? const PredictiveBackPageTransitionsBuilder()
    : const CupertinoPageTransitionsBuilder();

Brightness getBrightnessFromThemeMode(ThemeMode themeMode) {
  final themeBrightnessMapping = {
    ThemeMode.light: Brightness.light,
    ThemeMode.dark: Brightness.dark,
    ThemeMode.system:
        SchedulerBinding.instance.platformDispatcher.platformBrightness,
  };

  return themeBrightnessMapping[themeMode] ?? Brightness.dark;
}

ThemeMode getThemeMode(int themeModeIndex) {
  const themeModes = ThemeMode.values;
  if (themeModeIndex >= 0 && themeModeIndex < themeModes.length) {
    return themeModes[themeModeIndex];
  }
  return ThemeMode.dark;
}

ColorScheme getAppColorScheme(
  ColorScheme? lightColorScheme,
  ColorScheme? darkColorScheme,
) {
  if (useSystemColor.value &&
      lightColorScheme != null &&
      darkColorScheme != null) {
    // Temporary fix until this will be fixed: https://github.com/material-foundation/flutter-packages/issues/582

    (lightColorScheme, darkColorScheme) = tempGenerateDynamicColourSchemes(
      lightColorScheme,
      darkColorScheme,
    );
  }

  final selectedScheme = (brightness == Brightness.light)
      ? lightColorScheme
      : darkColorScheme;

  if (useSystemColor.value && selectedScheme != null) {
    return selectedScheme;
  }

  // Brand glassmorphism palette (dark) / seed-based light.
  if (brightness == Brightness.dark) {
    return WiyaDesign.darkColorScheme.copyWith(
      primary: primaryColorSetting,
      secondary: Color.lerp(
        primaryColorSetting,
        WiyaDesign.primaryBright,
        0.35,
      ),
      primaryContainer: Color.lerp(
        primaryColorSetting,
        WiyaDesign.primaryDeep,
        0.55,
      ),
    );
  }

  return ColorScheme.fromSeed(
    seedColor: primaryColorSetting,
  ).harmonized();
}

ThemeData getAppTheme(ColorScheme colorScheme) {
  final base = colorScheme.brightness == Brightness.light
      ? ThemeData.light()
      : ThemeData.dark();

  final isLight = colorScheme.brightness == Brightness.light;
  final isPureBlack =
      colorScheme.brightness == Brightness.dark && usePureBlackColor.value;
  final isGlassDark = colorScheme.brightness == Brightness.dark && !isPureBlack;

  // Pure black theme colors
  const pureBlack = Color(0xFF000000);
  const pureBlackElevated = Color(0xFF0A0A0A);
  const pureBlackContainer = Color(0xFF121212);
  const pureBlackContainerHigh = Color(0xFF1A1A1A);

  final effectiveColorScheme = isPureBlack
      ? colorScheme.copyWith(
          surface: pureBlack,
          surfaceContainerLowest: pureBlack,
          surfaceContainerLow: pureBlackElevated,
          surfaceContainer: pureBlackContainer,
          surfaceContainerHigh: pureBlackContainerHigh,
          surfaceContainerHighest: pureBlackContainerHigh,
        )
      : colorScheme;

  final bgColor = isLight
      ? effectiveColorScheme.surface
      : (isPureBlack
            ? pureBlack
            : (isGlassDark
                  ? WiyaDesign.background
                  : effectiveColorScheme.surface));

  final cardBgColor = isLight
      ? effectiveColorScheme.surfaceContainerLow
      : (isPureBlack
            ? pureBlackElevated
            : effectiveColorScheme.surfaceContainerHigh);

  final radius = BorderRadius.circular(WiyaDesign.cornerRadius);
  final radiusMedium = BorderRadius.circular(WiyaDesign.cornerRadiusMedium);

  return ThemeData(
    scaffoldBackgroundColor: bgColor,
    colorScheme: effectiveColorScheme,
    cardColor: cardBgColor,
    cardTheme: base.cardTheme.copyWith(
      elevation: 0,
      color: cardBgColor,
      shadowColor: effectiveColorScheme.primary.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: radius),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: bgColor,
      foregroundColor: effectiveColorScheme.primary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      systemOverlayStyle: isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        fontSize: 30,
        fontFamily: 'paytoneOne',
        fontWeight: FontWeight.w500,
        color: effectiveColorScheme.primary,
        letterSpacing: -0.5,
      ),
      toolbarHeight: 64,
      iconTheme: IconThemeData(
        color: effectiveColorScheme.onSurfaceVariant,
        size: 24,
      ),
      actionsIconTheme: IconThemeData(
        color: effectiveColorScheme.onSurfaceVariant,
        size: 24,
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      textColor: effectiveColorScheme.onSurface,
      iconColor: effectiveColorScheme.primary,
      shape: RoundedRectangleBorder(borderRadius: radiusMedium),
    ),
    iconTheme: IconThemeData(
      color: effectiveColorScheme.primary,
      size: 24,
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: effectiveColorScheme.primary,
      foregroundColor: effectiveColorScheme.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: effectiveColorScheme.primary,
        foregroundColor: effectiveColorScheme.onPrimary,
        elevation: 0,
        shadowColor: effectiveColorScheme.primary.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: effectiveColorScheme.primary,
        foregroundColor: effectiveColorScheme.onPrimary,
        elevation: 0,
        shadowColor: effectiveColorScheme.primary.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: effectiveColorScheme.primary,
        side: BorderSide(
          color: effectiveColorScheme.primary.withValues(alpha: 0.45),
        ),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: effectiveColorScheme.surfaceContainerHigh,
      selectedColor: effectiveColorScheme.primaryContainer,
      side: BorderSide(
        color: effectiveColorScheme.outline.withValues(alpha: 0.35),
      ),
      shape: RoundedRectangleBorder(borderRadius: radiusMedium),
      labelStyle: TextStyle(color: effectiveColorScheme.onSurface),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      year2023: false,
      trackHeight: 6,
      activeTrackColor: effectiveColorScheme.primary,
      inactiveTrackColor: effectiveColorScheme.surfaceContainerHighest,
      thumbColor: effectiveColorScheme.primary,
      overlayColor: effectiveColorScheme.primary.withValues(alpha: 0.16),
      thumbSize: WidgetStateProperty.all(const Size(10, 10)),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: isLight
          ? effectiveColorScheme.surfaceContainerLow
          : (isPureBlack
                ? pureBlackElevated
                : effectiveColorScheme.surfaceContainerHigh),
      modalBackgroundColor: isLight
          ? effectiveColorScheme.surfaceContainerLow
          : effectiveColorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(WiyaDesign.cornerRadius),
        ),
      ),
      showDragHandle: true,
      dragHandleColor: effectiveColorScheme.outline.withValues(alpha: 0.55),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      isDense: true,
      fillColor: isLight
          ? effectiveColorScheme.surfaceContainerHighest
          : (isPureBlack
                ? pureBlackContainerHigh
                : effectiveColorScheme.surfaceContainerHigh),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: WiyaDesign.primaryBright.withValues(alpha: isLight ? 0.08 : 0.18),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: effectiveColorScheme.primary.withValues(alpha: 0.65),
          width: 1.4,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(18, 14, 20, 14),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: isLight
          ? effectiveColorScheme.surfaceContainerLow
          : (isPureBlack
                ? pureBlackContainer
                : effectiveColorScheme.surfaceContainerHigh),
      shape: RoundedRectangleBorder(borderRadius: radius),
      elevation: 0,
      shadowColor: effectiveColorScheme.primary.withValues(alpha: 0.2),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      elevation: 0,
      height: floatingNavBarHeight,
      indicatorColor: effectiveColorScheme.primary.withValues(alpha: 0.22),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(
            color: effectiveColorScheme.primary,
            size: 24,
          );
        }
        return IconThemeData(
          color: effectiveColorScheme.onSurfaceVariant,
          size: 24,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            color: effectiveColorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          );
        }
        return TextStyle(
          color: effectiveColorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        );
      }),
    ),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      backgroundColor: bgColor,
      elevation: 0,
      indicatorColor: effectiveColorScheme.primary.withValues(alpha: 0.22),
      selectedIconTheme: IconThemeData(
        color: effectiveColorScheme.primary,
        size: 24,
      ),
      unselectedIconTheme: IconThemeData(
        color: effectiveColorScheme.onSurfaceVariant,
        size: 24,
      ),
      selectedLabelTextStyle: TextStyle(
        color: effectiveColorScheme.primary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: effectiveColorScheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: isLight
          ? effectiveColorScheme.surfaceContainerLow
          : (isPureBlack
                ? pureBlackContainer
                : effectiveColorScheme.surfaceContainerHigh),
      shape: RoundedRectangleBorder(borderRadius: radiusMedium),
      elevation: 0,
      shadowColor: effectiveColorScheme.primary.withValues(alpha: 0.18),
    ),
    dividerTheme: base.dividerTheme.copyWith(
      color: effectiveColorScheme.outlineVariant.withValues(alpha: 0.55),
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: effectiveColorScheme.secondaryContainer,
      contentTextStyle: TextStyle(
        color: effectiveColorScheme.onSecondaryContainer,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radiusMedium),
      elevation: 0,
      actionTextColor: effectiveColorScheme.primary,
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    useMaterial3: true,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: transitionsBuilder,
      },
    ),
  );
}
