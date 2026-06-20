// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/theme/brand.dart';

/// Reading-progress bar, themed with the brand gradient. Lays out **horizontal**
/// (page-flip manga) or **vertical** (webtoon / vertical scroll); tap or drag
/// anywhere along it to seek. The filled portion is the indigo→cyan brand
/// gradient with a soft glow, on a subtle rounded track — Komikku-clean but in
/// our theme.
class BrandPageSeekBar extends StatelessWidget {
  const BrandPageSeekBar({
    super.key,
    required this.currentValue,
    required this.maxValue,
    required this.onChanged,
    this.axis = Axis.horizontal,
    this.inverted = false,
    this.capsuleColor,
  });

  /// 0-based current page.
  final int currentValue;

  /// Total page count.
  final int maxValue;
  final ValueChanged<int> onChanged;
  final Axis axis;

  /// Flip the fill/seek direction (RTL paging).
  final bool inverted;

  /// Capsule background. Pass [readerNavSurface] in vertical (webtoon) mode so
  /// the bar shares ONE theme-surface colour with its jump buttons.
  final Color? capsuleColor;

  void _seek(Offset local, Size size) {
    final lastIndex = max(maxValue - 1, 1);
    var frac = axis == Axis.horizontal
        ? (local.dx / size.width)
        : (local.dy / size.height);
    frac = frac.clamp(0.0, 1.0);
    if (inverted) frac = 1 - frac;
    onChanged((frac * lastIndex).round());
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final lastIndex = max(maxValue - 1, 1);
    final progress = (currentValue / lastIndex).clamp(0.0, 1.0);
    final fill = inverted ? 1 - progress : progress;

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seek(d.localPosition, size),
          onHorizontalDragUpdate: axis == Axis.horizontal
              ? (d) => _seek(d.localPosition, size)
              : null,
          onVerticalDragUpdate: axis == Axis.vertical
              ? (d) => _seek(d.localPosition, size)
              : null,
          child: CustomPaint(
            size: Size.infinite,
            painter: _SeekPainter(
              axis: axis,
              fill: fill,
              scheme: cs,
              count: maxValue,
            ),
          ),
        );
      },
    );

    final numStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final current =
        Text("${(currentValue + 1).clamp(1, maxValue)}", style: numStyle);
    final total = Text("$maxValue", style: numStyle);
    const thickness = 26.0;
    // Gap between the page numbers and the bar — Komikku keeps them clear of
    // the slider (the "6 / 15 touching the slider" complaint).
    const gap = SizedBox.square(dimension: 10);

    final content = axis == Axis.horizontal
        ? Row(
            children: [
              inverted ? total : current,
              gap,
              Expanded(child: SizedBox(height: thickness, child: bar)),
              gap,
              inverted ? current : total,
            ],
          )
        : Column(
            children: [
              current,
              gap,
              Expanded(child: SizedBox(width: thickness, child: bar)),
              gap,
              total,
            ],
          );

    return Card(
      color: capsuleColor ??
          context.theme.appBarTheme.backgroundColor?.withValues(alpha: .7),
      shape: RoundedRectangleBorder(borderRadius: KBorderRadius.r32.radius),
      child: Padding(
        padding: axis == Axis.horizontal
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
        child: content,
      ),
    );
  }
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.axis,
    required this.fill,
    required this.scheme,
    required this.count,
  });

  final Axis axis;
  final double fill;
  final ColorScheme scheme;

  /// Page count — one tick dot per page (Komikku style).
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    const t = 9.0;
    final radius = Radius.circular(t / 2);
    final horizontal = axis == Axis.horizontal;
    final length = horizontal ? size.width : size.height;
    final cross = horizontal ? size.height / 2 : size.width / 2;

    Rect bar(double from, double to) => horizontal
        ? Rect.fromLTRB(from, cross - t / 2, to, cross + t / 2)
        : Rect.fromLTRB(cross - t / 2, from, cross + t / 2, to);
    Offset along(double d) =>
        horizontal ? Offset(d, cross) : Offset(cross, d);

    // Track — accent-tinted (Komikku's slider inactive track), subtle.
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar(0, length), radius),
      Paint()..color = scheme.primary.withValues(alpha: 0.22),
    );

    // Gradient fill up to the current position.
    final fillEnd = (length * fill).clamp(0.0, length);
    if (fillEnd > 0.5) {
      final filled = bar(0, fillEnd);
      canvas.drawRRect(
        RRect.fromRectAndRadius(filled, radius),
        Paint()..shader = brandGradient(scheme).createShader(filled),
      );
    }

    // Per-page tick dots — skip when too dense to stay clean.
    if (count > 1 && count <= 80) {
      final dot = Paint()..color = scheme.onSurface.withValues(alpha: 0.5);
      for (var i = 0; i < count; i++) {
        canvas.drawCircle(along(length * (i / (count - 1))), 2.0, dot);
      }
    }

    // Marker line at the current position (perpendicular to the bar), painted
    // with the brand gradient + a soft glow — Komikku's line, our colours.
    final pos = length * fill;
    const half = 13.0;
    const mkt = 4.0;
    final p1 = horizontal ? Offset(pos, cross - half) : Offset(cross - half, pos);
    final p2 = horizontal ? Offset(pos, cross + half) : Offset(cross + half, pos);
    // Glow.
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = scheme.primary.withValues(alpha: 0.55)
        ..strokeWidth = mkt + 5
        ..strokeCap = StrokeCap.round
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 5),
    );
    // Gradient marker.
    final markerRect = Rect.fromPoints(p1, p2).inflate(mkt);
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..shader = brandGradient(scheme).createShader(markerRect)
        ..strokeWidth = mkt
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.fill != fill ||
      old.axis != axis ||
      old.scheme != scheme ||
      old.count != count;
}
