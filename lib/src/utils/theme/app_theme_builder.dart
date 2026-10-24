import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_theme.dart';
import 'app_color_scheme.dart';
import 'brand.dart';
import 'oklch_contrast.dart';
import 'theme_tokens.dart';

/// The [ColorScheme] a theme uses at [brightness]; Custom is seed-derived.
ColorScheme schemeFor(
  AppTheme theme,
  Brightness brightness,
  Color customSeed,
) {
  if (theme != AppTheme.custom) {
    return schemeFromTokens(tokensFor(theme, brightness), brightness);
  }
  final seeded = ColorScheme.fromSeed(
    seedColor: customSeed,
    brightness: brightness,
  );
  if (brightness == Brightness.light) return seeded;
  return seeded.copyWith(
    primary: solveContrast(
      seeded.primary,
      seeded.surface,
      contrastRatio(seeded.onSurfaceVariant, seeded.surface),
      lighten: true,
    ),
    onPrimary: const Color(0xFF0A0A12),
  );
}

/// Named themes use brand tokens; Custom is seed-derived. AMOLED affects dark mode only.
ThemeData buildAppTheme({
  required AppTheme theme,
  required Brightness brightness,
  required Color customSeed,
  required bool amoled,
}) {
  final tokens = theme == AppTheme.custom ? null : tokensFor(theme, brightness);
  ColorScheme scheme = schemeFor(theme, brightness, customSeed);

  if (brightness == Brightness.dark && amoled) {
    scheme = applyAmoled(scheme);
  }

  final navFill =
      tokens?.accentFill ??
      (brightness == Brightness.dark
          ? solveContrast(scheme.primary, scheme.onSurface, 7, lighten: false)
          : null);

  // Named light themes use their own gradients and on-accent colors.
  final brandColors = BrandColors(
    gradient: tokens?.grad ?? schemeBrandGradient(scheme),
    onGradient: tokens?.onAccent ?? const Color(0xFF0B0D1A),
    success: brandSuccessColor(brightness),
    neutral: theme == AppTheme.mono && brightness == Brightness.light,
    navSelectedFill: navFill,
  );

  final primary = scheme.primary;
  final outline = scheme.outlineVariant;
  final brightPrimary = brandBrightAccent(scheme);

  ButtonStyle filledLike() => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled)
          ? scheme.onSurface.withValues(alpha: 0.12)
          : primary,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled)
          ? scheme.onSurface.withValues(alpha: 0.38)
          : scheme.onPrimary,
    ),
    shadowColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.6)),
    elevation: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? 0 : 6,
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );

  return ThemeData(
    useMaterial3: true,
    // Leave platform font fallback available for scripts Inter does not cover.
    fontFamily: 'Inter',
    colorScheme: scheme,
    extensions: [brandColors],
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Match system-bar icon brightness to the surface for contrast.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: brightness == Brightness.dark
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: scheme.surface,
        systemNavigationBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) => Icon(
        FluentIcons.arrow_left_24_regular,
        semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
      ),
      closeButtonIconBuilder: (context) =>
          const Icon(FluentIcons.dismiss_24_regular),
    ),
    tabBarTheme: const TabBarThemeData(tabAlignment: TabAlignment.center),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      elevation: 0,
      indicatorColor: navFill ?? scheme.secondaryContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? (navFill != null
                    ? scheme.onSurface
                    : scheme.onSecondaryContainer)
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((s) {
        final selected = s.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          height: 1.33,
          letterSpacing: 0.5,
          overflow: TextOverflow.ellipsis,
          fontWeight: selected && navFill != null
              ? FontWeight.w700
              : FontWeight.w500,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: navFill ?? primary.withValues(alpha: 0.22),
      selectedIconTheme: IconThemeData(
        color: navFill != null ? scheme.onSurface : primary,
      ),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: navFill != null ? scheme.onSurface : primary,
        fontWeight: navFill != null ? FontWeight.w700 : FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
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
    chipTheme: tokens?.accentBg != null
        ? ChipThemeData(
            backgroundColor: Colors.transparent,
            selectedColor: tokens!.accentBg,
            side: WidgetStateBorderSide.resolveWith(
              (s) => BorderSide(
                color: s.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.outlineVariant,
              ),
            ),
            labelStyle: TextStyle(color: scheme.onSurface),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          )
        : ChipThemeData(
            backgroundColor: primary.withValues(alpha: 0.12),
            side: BorderSide(color: primary.withValues(alpha: 0.40)),
            labelStyle: TextStyle(color: scheme.onSurface),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
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
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(brightPrimary),
      ),
    ),
  );
}

ScrollbarThemeData wideScreenScrollbarTheme(ColorScheme scheme) =>
    ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(true),
      trackVisibility: const WidgetStatePropertyAll(false),
      thickness: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)
            ? 10
            : 8,
      ),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.22),
      ),
    );
