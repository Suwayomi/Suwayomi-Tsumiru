import 'package:flutter/material.dart';

import '../../widgets/custom_circular_progress_indicator.dart';

/// Brand visual language — the SINGLE source for the things Flutter's Material
/// [ThemeData] cannot express (gradients + glow). Everything here derives from
/// the active [ColorScheme], which is built from the theme-kit tokens, so all
/// three named themes (Indigo Night / Carbon / Plum) + Custom work for free.
///
/// Do NOT inline gradients/colors at call sites — use these components.

/// The brand gradient. Mirrors theme-kit `--grad: linear-gradient(135deg,
/// accent, accent2)` exactly: 135° == top-left → bottom-right, accent first.
LinearGradient brandGradient(ColorScheme cs) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [cs.primary, cs.secondary],
    );

/// The brand glow. Mirrors theme-kit `--glow` (accent at ~35%) as a soft shadow.
List<BoxShadow> brandGlow(ColorScheme cs) => [
      BoxShadow(
        color: cs.primary.withValues(alpha: 0.35),
        blurRadius: 22,
        spreadRadius: -2,
        offset: const Offset(0, 5),
      ),
    ];

/// The gradient is bright, so on-gradient content (text/icons) is dark.
const Color onBrandGradient = Color(0xFF0B0D1A);

/// The single reader-chrome surface (top/bottom bars, seekbars, skip buttons) so
/// the chrome reads uniform. Near-opaque — 0.9 dark / 0.95 light; a
/// lower alpha washes out over white webtoon pages.
Color readerNavSurface(ColorScheme cs) => cs.surface.withValues(
      alpha: cs.brightness == Brightness.dark ? 0.9 : 0.95,
    );

/// A lighter, more vibrant accent for text/outline actions (links, "Uninstall").
Color brandBrightAccent(ColorScheme cs) =>
    Color.lerp(cs.primary, Colors.white, 0.22)!;

/// Deterministic hue (0-360) for a label — same genre always gets the same
/// color. Mirrors the playground's `hueFor`: h = (h*31 + codeUnit) % 360.
double brandHueFor(String label) {
  var h = 0;
  for (final c in label.codeUnits) {
    h = (h * 31 + c) % 360;
  }
  return h.toDouble();
}

/// An icon painted with the brand gradient (for the downloaded check-circle,
/// etc.). Single source — do not inline ShaderMask + gradient at call sites.
Widget brandGradientIcon(
  BuildContext context,
  IconData icon, {
  double size = 24,
}) {
  final cs = Theme.of(context).colorScheme;
  return ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (bounds) => brandGradient(cs).createShader(bounds),
    child: Icon(icon, size: size, color: Colors.white),
  );
}

Widget _brandRow({
  required Widget label,
  Widget? icon,
  required bool expand,
  Color content = onBrandGradient,
}) =>
    Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          IconTheme.merge(
            data: IconThemeData(color: content, size: 20),
            child: icon,
          ),
          const SizedBox(width: 8),
        ],
        // Flexible so a long label (e.g. "Downloading 14") ellipsises instead
        // of overflowing the button's width.
        Flexible(
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: content,
              fontWeight: FontWeight.w700,
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

/// Primary action — brand gradient + glow, dark content. (No Material fill.)
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
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: brandGradient(cs),
        borderRadius: BorderRadius.circular(14),
        boxShadow: brandGlow(cs),
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
                    ? const MiniCircularProgressIndicator(
                        color: onBrandGradient)
                    : _brandRow(label: label, icon: icon, expand: expand),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action — translucent glass fill + accent border + bright text.
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
        color: Colors.white.withValues(alpha: 0.05),
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
                  label: label,
                  icon: icon,
                  expand: expand,
                  content: accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small circular **glass** brand button — translucent fill + accent border +
/// bright accent glyph. Single source for round brand actions (reader
/// chapter-end jumps, etc.).
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
        color: Colors.white.withValues(alpha: 0.06),
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

/// Filled round icon button for the reader vertical nav. Filled
/// with [color] (the shared [readerNavSurface] so it matches the bar capsule
/// exactly), glyph in the theme `primary`. [quarterTurns] rotates the icon so
/// the chapter skip glyphs point up / down like the vertical slider.
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

/// Genre / tag chip — glass fill tinted with a UNIQUE per-label color
/// (hue derived from the label, so every genre is visually distinct).
class BrandChip extends StatelessWidget {
  const BrandChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final hue = brandHueFor(label);
    final bg = HSLColor.fromAHSL(0.16, hue, 0.70, 0.55).toColor();
    final border = HSLColor.fromAHSL(0.45, hue, 0.70, 0.60).toColor();
    final fg = HSLColor.fromAHSL(1, hue, 0.85, 0.78).toColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

/// Floating action — brand gradient + glow pill, dark content.
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
        gradient: brandGradient(cs),
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
            child: _brandRow(label: label, icon: icon, expand: false),
          ),
        ),
      ),
    );
  }
}
