import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../../widgets/custom_circular_progress_indicator.dart';
import '../../widgets/hover_tap_target.dart';
import '../motion/reduce_motion.dart';

/// Shared brand gradients and glow; use these components instead of inlining colors.

/// Default 135° gradient: accent at top-left, accent2 at bottom-right.
LinearGradient schemeBrandGradient(ColorScheme cs) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [cs.primary, cs.secondary],
);

List<BoxShadow> brandGlow(ColorScheme cs) => [
  BoxShadow(
    color: cs.primary.withValues(alpha: 0.35),
    blurRadius: 22,
    spreadRadius: -2,
    offset: const Offset(0, 5),
  ),
];

/// Active theme gradient and on-accent color; light themes may reverse gradient direction.
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.gradient,
    required this.onGradient,
    required this.success,
    this.neutral = false,
    this.navSelectedFill,
  });

  final Gradient gradient;

  final Color onGradient;

  final Color success;

  /// Monochrome light removes hues from genre chips and cover backdrops.
  final bool neutral;

  final Color? navSelectedFill;

  @override
  BrandColors copyWith({
    Gradient? gradient,
    Color? onGradient,
    Color? success,
    bool? neutral,
    Color? navSelectedFill,
  }) => BrandColors(
    gradient: gradient ?? this.gradient,
    onGradient: onGradient ?? this.onGradient,
    success: success ?? this.success,
    neutral: neutral ?? this.neutral,
    navSelectedFill: navSelectedFill ?? this.navSelectedFill,
  );

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      gradient: Gradient.lerp(gradient, other.gradient, t)!,
      onGradient: Color.lerp(onGradient, other.onGradient, t)!,
      success: Color.lerp(success, other.success, t)!,
      neutral: t < 0.5 ? neutral : other.neutral,
      navSelectedFill: Color.lerp(navSelectedFill, other.navSelectedFill, t),
    );
  }

  static BrandColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<BrandColors>() ??
        BrandColors(
          gradient: schemeBrandGradient(theme.colorScheme),
          onGradient: const Color(0xFF0B0D1A),
          success: brandSuccessColor(theme.colorScheme.brightness),
        );
  }
}

/// Success green meets 4.5:1 contrast against the surface at each brightness.
Color brandSuccessColor(Brightness brightness) => brightness == Brightness.dark
    ? const Color(0xFF34E0A1)
    : const Color(0xFF00754A);

/// Star amber darkens in light mode to meet 3:1 contrast.
Color brandStarColor(Brightness brightness) =>
    brightness == Brightness.dark ? Colors.amber : const Color(0xFFB7791F);

/// Colors over cover art remain independent of the app theme.
abstract final class OnImage {
  static const text = Colors.white;
  static const shadow = Colors.black;
  static const scrim = Color(0xAA000000);
}

/// Shared reader chrome surface; high opacity preserves contrast over white pages.
Color readerNavSurface(ColorScheme cs) =>
    cs.surface.withValues(alpha: cs.brightness == Brightness.dark ? 0.9 : 0.95);

/// Brighten dark-mode text actions only; light mode retains primary contrast.
Color brandBrightAccent(ColorScheme cs) => cs.brightness == Brightness.light
    ? cs.primary
    : Color.lerp(cs.primary, Colors.white, 0.22)!;

/// Stable label hue in 0–360 degrees.
double brandHueFor(String label) {
  var h = 0;
  for (final c in label.codeUnits) {
    h = (h * 31 + c) % 360;
  }
  return h.toDouble();
}

Widget brandGradientIcon(
  BuildContext context,
  IconData icon, {
  double size = 24,
}) {
  return ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) =>
        BrandColors.of(context).gradient.createShader(bounds),
    child: Icon(icon, size: size, color: Colors.white),
  );
}

Widget _brandRow({
  required BuildContext context,
  required Widget label,
  Widget? icon,
  required bool expand,
  Color? content,
}) {
  final color = content ?? BrandColors.of(context).onGradient;
  return Row(
    mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (icon != null) ...[
        IconTheme.merge(
          data: IconThemeData(color: color, size: 20),
          child: icon,
        ),
        const SizedBox(width: 8),
      ],
      // Flexible allows long button labels to ellipsize.
      Flexible(
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          child: label,
        ),
      ),
    ],
  );
}

class BrandButton extends StatelessWidget {
  const BrandButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
    this.height = 46,
    this.expand = true,
  });

  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;
  final bool loading;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brand = BrandColors.of(context);
    final disabled = onPressed == null && !loading;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: disabled ? null : brand.gradient,
        color: disabled ? cs.onSurface.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: disabled ? null : brandGlow(cs),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: loading ? null : onPressed,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: loading
                    ? MiniCircularProgressIndicator(
                        size: 16,
                        padding: const EdgeInsets.all(8),
                        color: brand.onGradient,
                      )
                    : _brandRow(
                        context: context,
                        label: label,
                        icon: icon,
                        expand: expand,
                        content: disabled
                            ? cs.onSurface.withValues(alpha: 0.38)
                            : null,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BrandGlassButton extends StatelessWidget {
  const BrandGlassButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.height = 46,
    this.expand = true,
  });

  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = brandBrightAccent(cs);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: _brandRow(
                  context: context,
                  label: label,
                  icon: icon,
                  expand: expand,
                  content: onPressed == null
                      ? cs.onSurface.withValues(alpha: 0.38)
                      : accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BrandCircleButton extends StatelessWidget {
  const BrandCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 42,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.onSurface.withValues(alpha: 0.06),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.55, color: brandBrightAccent(cs)),
          ),
        ),
      ),
    );
  }
}

/// Filled reader navigation button; quarterTurns rotates chapter-skip glyphs.
class BrandFilledCircleButton extends StatelessWidget {
  const BrandFilledCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.color,
    this.size = 44,
    this.quarterTurns = 0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final double size;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: RotatedBox(
              quarterTurns: quarterTurns,
              child: Icon(
                icon,
                size: size * 0.5,
                color: enabled
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef ChipColors = ({Color fill, Color border, Color text});

final _lightChipColors = <int, ChipColors>{};

/// Genre chip colors use HCT in light mode to maintain contrast across hues.
ChipColors brandChipColors(double hue, Brightness brightness) {
  if (brightness == Brightness.dark) {
    return (
      fill: HSLColor.fromAHSL(0.16, hue, 0.70, 0.55).toColor(),
      border: HSLColor.fromAHSL(0.45, hue, 0.70, 0.60).toColor(),
      text: HSLColor.fromAHSL(1, hue, 0.85, 0.78).toColor(),
    );
  }
  // Cache the HCT solver result; integer hues bound this to 360 entries.
  return _lightChipColors.putIfAbsent(hue.round(), () {
    // Retain the genre color family across light and dark modes.
    final hct = Hct.fromInt(
      HSLColor.fromAHSL(1, hue, 0.85, 0.55).toColor().toARGB32(),
    ).hue;
    return (
      // Opaque fill keeps contrast independent of the theme surface.
      fill: Color(Hct.from(hct, 40, 92).toInt()),
      border: Color(Hct.from(hct, 40, 80).toInt()),
      text: Color(Hct.from(hct, 50, 34).toInt()),
    );
  });
}

class BrandChip extends StatelessWidget {
  const BrandChip({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = BrandColors.of(context).neutral
        ? (
            fill: cs.surfaceContainer,
            border: cs.outlineVariant,
            text: cs.onSurface,
          )
        : brandChipColors(brandHueFor(label), cs.brightness);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.text,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
    if (onTap == null) return chip;
    return HoverTapTarget(
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            chip,
            Positioned.fill(
              child: AnimatedContainer(
                duration: Duration(
                  milliseconds: context.reduceMotion ? 0 : 120,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: cs.onSurface.withValues(alpha: hovered ? 0.08 : 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BrandFab extends StatelessWidget {
  const BrandFab({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: BrandColors.of(context).gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: brandGlow(cs),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: _brandRow(
              context: context,
              label: label,
              icon: icon,
              expand: false,
            ),
          ),
        ),
      ),
    );
  }
}
