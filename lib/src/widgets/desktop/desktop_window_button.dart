// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

part of 'desktop_title_bar.dart';

class _BreezeButton extends StatefulWidget {
  const _BreezeButton({required this.glyph, required this.onPressed, this.label});
  final int glyph;
  final VoidCallback onPressed;
  final String? label;

  @override
  State<_BreezeButton> createState() => _BreezeButtonState();
}

class _BreezeButtonState extends State<_BreezeButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hovered || _pressed || _focused;
    final close = widget.glyph == 3;
    final opacity = !active ? 0.0 : (close ? 1.0 : (_pressed ? 0.28 : 0.18));
    final background = close && _pressed
        ? Color.alphaBlend(scheme.onError.withValues(alpha: 0.15), scheme.error)
        : (close ? scheme.error : scheme.onSurface);
    return Semantics(
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
          dimension: 28,
          child: Center(
            child: CustomPaint(
              size: const Size.square(18),
              painter: _BreezeGlyph(
                widget.glyph,
                active && close ? scheme.onError : scheme.onSurface,
                background.withValues(alpha: opacity),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BreezeGlyph extends CustomPainter {
  const _BreezeGlyph(this.glyph, this.foreground, this.background);
  final int glyph;
  final Color foreground;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(size.center(Offset.zero), 9, Paint()..color = background);
    final points = switch (glyph) {
      0 => const [Offset(5, 7), Offset(9, 11), Offset(13, 7)],
      1 => const [Offset(5, 11), Offset(9, 7), Offset(13, 11)],
      2 => const [Offset(9, 4), Offset(14, 9), Offset(9, 14), Offset(4, 9)],
      _ => const [Offset(5, 5), Offset(13, 13)],
    };
    final path = Path()..addPolygon(points, glyph == 2);
    if (glyph == 3) {
      path.moveTo(13, 5);
      path.lineTo(5, 13);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = foreground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BreezeGlyph old) =>
      glyph != old.glyph ||
      foreground != old.foreground ||
      background != old.background;
}
