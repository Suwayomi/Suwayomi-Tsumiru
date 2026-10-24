// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:animated_vector/animated_vector.dart';
import 'package:flutter/material.dart';

import '../../utils/motion/reduce_motion.dart';

/// Animate selection changes; mounting selected shows the settled frame without replaying.
class AnimatedNavIcon extends StatefulWidget {
  const AnimatedNavIcon({
    super.key,
    required this.vector,
    required this.selected,
  });

  final AnimatedVectorData vector;
  final bool selected;

  @override
  State<AnimatedNavIcon> createState() => _AnimatedNavIconState();
}

class _AnimatedNavIconState extends State<AnimatedNavIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.vector.duration,
    value: widget.selected ? 1 : 0,
  );

  @override
  void didUpdateWidget(AnimatedNavIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vector != oldWidget.vector) {
      _controller.duration = widget.vector.duration;
    }
    if (widget.selected == oldWidget.selected) return;
    if (context.reduceMotion) {
      _controller.value = widget.selected ? 1 : 0;
    } else if (widget.selected) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = iconTheme.size ?? 24;
    return AnimatedVector(
      vector: widget.vector,
      progress: _controller,
      size: Size.square(size),
      applyTheme: true,
      // AnimatedVector ignores the local IconTheme; resolve per-state colors here.
      color: iconTheme.color,
    );
  }
}
