// lib/src/utils/theme/app_theme_builder.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_theme.dart';
import 'app_color_scheme.dart';
import 'theme_tokens.dart';

/// Single source of truth for app ThemeData. Named themes use brand tokens;
/// custom uses ColorScheme.fromSeed. AMOLED applies only to dark.
ThemeData buildAppTheme({
  required AppTheme theme,
  required Brightness brightness,
  required Color customSeed,
  required bool amoled,
}) {
  ColorScheme scheme = theme == AppTheme.custom
      ? ColorScheme.fromSeed(seedColor: customSeed, brightness: brightness)
      : schemeFromTokens(tokensFor(theme, brightness), brightness);

  if (brightness == Brightness.dark && amoled) {
    scheme = applyAmoled(scheme);
  }

  final primary = scheme.primary;
  final outline = scheme.outlineVariant;
  // A lighter, more vibrant blue for text/outline actions (Uninstall, links…).
  final brightPrimary = Color.lerp(primary, Colors.white, 0.22)!;

  ButtonStyle filledLike() => ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(primary),
        foregroundColor: WidgetStatePropertyAll(scheme.onPrimary),
        shadowColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.6)),
        elevation: const WidgetStatePropertyAll(6),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    // Left-aligned titles app-wide; flat surface app bar (no grey elevation).
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Make the status-bar and bottom system-navigation-bar icons track the
      // theme brightness. Without this the system nav-bar icons stayed light
      // and went invisible on the light surface in light themes.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            brightness == Brightness.dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: scheme.surface,
        systemNavigationBarIconBrightness:
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    ),
    tabBarTheme: const TabBarThemeData(tabAlignment: TabAlignment.center),
    // Bottom navigation: brand-tinted selected indicator + accent selection.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: 0,
      indicatorColor: primary.withValues(alpha: 0.22),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? primary
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: primary.withValues(alpha: 0.22),
      selectedIconTheme: IconThemeData(color: primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle:
          TextStyle(color: primary, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    // Accent the leading icons of list rows (More/Settings etc.).
    listTileTheme: ListTileThemeData(
      iconColor: primary,
      selectedColor: primary,
      selectedTileColor: primary.withValues(alpha: 0.16),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: outline),
      ),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: primary.withValues(alpha: 0.12),
      side: BorderSide(color: primary.withValues(alpha: 0.40)),
      labelStyle: TextStyle(color: scheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? primary : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? primary.withValues(alpha: 0.45)
            : scheme.surfaceContainerHighest,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: primary,
      inactiveTrackColor: primary.withValues(alpha: 0.22),
      thumbColor: primary,
      overlayColor: primary.withValues(alpha: 0.18),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: scheme.onPrimary,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: filledLike()),
    elevatedButtonTheme: ElevatedButtonThemeData(style: filledLike()),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(brightPrimary),
        side: WidgetStatePropertyAll(
          BorderSide(color: primary.withValues(alpha: 0.5)),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          ButtonStyle(foregroundColor: WidgetStatePropertyAll(brightPrimary)),
    ),
  );
}
