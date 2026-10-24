// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../constants/gen/assets.gen.dart';
import '../utils/extensions/custom_extensions.dart';
import '../utils/motion/reduce_motion.dart';

class CenterSorayomiShimmerIndicator extends StatelessWidget {
  const CenterSorayomiShimmerIndicator({super.key, this.value});

  final double? value;
  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          height: context.height * .35,
          width: context.width * .35,
          child: const SorayomiShimmerIndicator(),
        ),
      );
}

/// Reserve space immediately but delay painting to avoid flashing on fast cache loads.
class DelayedShimmer extends StatefulWidget {
  const DelayedShimmer({super.key, this.delay = const Duration(milliseconds: 200)});

  final Duration delay;

  @override
  State<DelayedShimmer> createState() => _DelayedShimmerState();
}

class _DelayedShimmerState extends State<DelayedShimmer> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const indicator = CenterSorayomiShimmerIndicator();
    if (context.reduceMotion) {
      return Opacity(opacity: _visible ? 1 : 0, child: indicator);
    }
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: indicator,
    );
  }
}

class SorayomiShimmerIndicator extends StatelessWidget {
  const SorayomiShimmerIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final baseColor = context.colorScheme.surface;
    final icon = AssetImage(Assets.icons.darkIcon.path);
    if (context.reduceMotion) {
      return ImageIcon(icon, color: context.colorScheme.primary);
    }
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: context.theme.colorScheme.primary,
      child: ImageIcon(icon),
    );
  }
}

Size resolveIconButtonBox(BuildContext context) {
  final theme = Theme.of(context);
  final style = IconButtonTheme.of(context).style;
  const states = <WidgetState>{};
  final fixed = style?.fixedSize?.resolve(states);
  if (fixed != null && fixed.width.isFinite && fixed.height.isFinite) {
    return fixed;
  }
  final density = style?.visualDensity ?? theme.visualDensity;
  final tapTarget = style?.tapTargetSize ?? theme.materialTapTargetSize;
  final adjustment = density.baseSizeAdjustment;
  if (tapTarget == MaterialTapTargetSize.shrinkWrap) {
    final minimum = style?.minimumSize?.resolve(states) ?? const Size(40, 40);
    final icon = resolveIconButtonIconSize(context);
    final width = minimum.width + adjustment.dx;
    final height = minimum.height + adjustment.dy;
    return Size(width > icon ? width : icon, height > icon ? height : icon);
  }
  return Size(
    kMinInteractiveDimension + adjustment.dx,
    kMinInteractiveDimension + adjustment.dy,
  );
}

double resolveIconButtonIconSize(BuildContext context) =>
    IconButtonTheme.of(context).style?.iconSize?.resolve({}) ??
    IconTheme.of(context).size ??
    24.0;

class MiniCircularProgressIndicator extends StatelessWidget {
  const MiniCircularProgressIndicator({
    super.key,
    this.color,
    this.value,
    this.padding,
    this.size,
  });
  final Color? color;
  final double? value;
  final EdgeInsetsGeometry? padding;
  final double? size;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? EdgeInsets.zero,
        child: SizedBox.square(
          dimension: size ?? resolveIconButtonIconSize(context),
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: color,
            value: value,
          ),
        ),
      );
}
