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

/// A lighter, more vibrant accent for text/outline actions (links, "Uninstall").
Color brandBrightAccent(ColorScheme cs) =>
    Color.lerp(cs.primary, Colors.white, 0.22)!;

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
        DefaultTextStyle.merge(
          style: TextStyle(
            color: content,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          child: label,
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
