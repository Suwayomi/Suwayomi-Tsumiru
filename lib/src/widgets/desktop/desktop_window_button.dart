// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

part of 'desktop_title_bar.dart';

enum _WindowGlyph { minimize, maximize, restore, close }

class _AdwaitaButton extends StatefulWidget {
  const _AdwaitaButton({required this.glyph, required this.onPressed, this.label});
  final _WindowGlyph glyph;
  final VoidCallback onPressed;
  final String? label;

  @override
  State<_AdwaitaButton> createState() => _AdwaitaButtonState();
}

class _AdwaitaButtonState extends State<_AdwaitaButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opacity = _pressed ? 0.30 : (_hovered || _focused ? 0.20 : 0.10);
    final destructive = widget.glyph == _WindowGlyph.close &&
        (_hovered || _focused || _pressed);
    final foreground = destructive ? scheme.onError : scheme.onSurface;
    final icon = TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: foreground, end: foreground),
      duration: const Duration(milliseconds: 200),
      curve: const Cubic(0.25, 0.46, 0.45, 0.94),
      builder: (context, color, child) => CustomPaint(size: const Size.square(16),
        painter: _AdwaitaGlyph(widget.glyph, color!),
      ),
    );
    final button = Semantics(
      label: widget.label,
      child: InkWell(
        onTap: widget.onPressed,
        onHover: (value) => setState(() => _hovered = value),
        onHighlightChanged: (value) => setState(() => _pressed = value),
        onFocusChange: (value) => setState(() => _focused = value),
        overlayColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: 0),
        ),
        child: SizedBox.square(
          dimension: _linuxWindowButtonHitSize,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: const Cubic(0.25, 0.46, 0.45, 0.94),
              width: _linuxWindowButtonCircleSize,
              height: _linuxWindowButtonCircleSize,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: destructive
                    ? scheme.error
                    : scheme.onSurface.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
    return Material(type: MaterialType.transparency, child: button);
  }
}

class _AdwaitaGlyph extends CustomPainter {
  const _AdwaitaGlyph(this.glyph, this.foreground);
  final _WindowGlyph glyph;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    switch (glyph) {
      case _WindowGlyph.minimize:
        path.moveTo(4, 11);
        path.lineTo(12, 11);
      case _WindowGlyph.maximize:
        path.addRect(const Rect.fromLTWH(3.5, 3.5, 9, 9));
      case _WindowGlyph.restore:
        path.addRect(const Rect.fromLTWH(5.5, 2.5, 7, 7));
        path.addRect(const Rect.fromLTWH(2.5, 5.5, 7, 7));
      case _WindowGlyph.close:
        path.moveTo(4, 4);
        path.lineTo(12, 12);
        path.moveTo(12, 4);
        path.lineTo(4, 12);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = foreground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(_AdwaitaGlyph old) =>
      glyph != old.glyph || foreground != old.foreground;
}
