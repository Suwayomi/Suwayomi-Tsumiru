// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/navigation_bar_data.dart';

/// Plays the motion forward on selection, in reverse on deselection.
class NavMotionIcon extends StatefulWidget {
  const NavMotionIcon(this.data, {super.key, required this.selected});

  final NavigationBarData data;
  final bool selected;

  @override
  State<NavMotionIcon> createState() => _NavMotionIconState();
}

TweenSequence<double> _keys(List<double> values, List<double> stops) {
  return TweenSequence<double>([
    for (var i = 0; i < values.length - 1; i++)
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: values[i], end: values[i + 1]),
        weight: stops[i + 1] - stops[i],
      ),
  ]);
}

TweenSequence<double>? _rotationOf(NavMotion motion) => switch (motion) {
  NavMotion.library => _keys(const [0, -16, 4, 0], const [0, 0.45, 0.75, 1]),
  NavMotion.history => _keys(const [0, -360], const [0, 1]),
  NavMotion.browse => _keys(const [0, 380, 360], const [0, 0.75, 1]),
  _ => null,
};

TweenSequence<double>? _shiftYOf(NavMotion motion) => switch (motion) {
  NavMotion.updates => _keys(const [0, -4, 0], const [0, 0.5, 1]),
  NavMotion.downloads => _keys(const [0, 5, -2, 0], const [0, 0.4, 0.7, 1]),
  _ => null,
};

TweenSequence<double>? _scaleOf(NavMotion motion) => switch (motion) {
  NavMotion.updates => _keys(const [1, 1.12, 1], const [0, 0.5, 1]),
  _ => null,
};

TweenSequence<double>? _scaleXOf(NavMotion motion) => switch (motion) {
  NavMotion.more => _keys(const [1, 1.3, 0.92, 1], const [0, 0.4, 0.7, 1]),
  _ => null,
};

TweenSequence<double>? _scaleYOf(NavMotion motion) => switch (motion) {
  NavMotion.more => _keys(const [1, 0.85, 1.08, 1], const [0, 0.4, 0.7, 1]),
  _ => null,
};

class _NavMotionIconState extends State<NavMotionIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: widget.selected ? 1 : 0,
  );
  late CurvedAnimation _curved;
  Animation<double>? _rotation;
  Animation<double>? _shiftY;
  Animation<double>? _scale;
  Animation<double>? _scaleX;
  Animation<double>? _scaleY;

  @override
  void initState() {
    super.initState();
    _createAnimations();
  }

  void _createAnimations() {
    final motion = widget.data.motion;
    _curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.fastOutSlowIn,
    );
    _rotation = _rotationOf(motion)?.animate(_curved);
    _shiftY = _shiftYOf(motion)?.animate(_curved);
    _scale = _scaleOf(motion)?.animate(_curved);
    _scaleX = _scaleXOf(motion)?.animate(_curved);
    _scaleY = _scaleYOf(motion)?.animate(_curved);
  }

  @override
  void didUpdateWidget(NavMotionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data.motion != oldWidget.data.motion) {
      _curved.dispose();
      _createAnimations();
    }
    if (widget.selected == oldWidget.selected) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.selected ? 1 : 0;
    } else if (widget.selected) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glyphs = AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: Icon(
        widget.selected ? widget.data.activeIcon : widget.data.icon,
        key: ValueKey(widget.selected),
      ),
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        var result = child!;
        final angle = _rotation?.value;
        if (angle != null) {
          result = Transform.rotate(
            angle: angle * math.pi / 180,
            alignment: Alignment.center,
            child: result,
          );
        }
        final uniform = _scale?.value;
        if (uniform != null) {
          result = Transform.scale(
            scale: uniform,
            alignment: Alignment.center,
            child: result,
          );
        }
        final sx = _scaleX?.value;
        final sy = _scaleY?.value;
        if (sx != null && sy != null) {
          result = Transform.scale(
            scaleX: sx,
            scaleY: sy,
            alignment: Alignment.center,
            child: result,
          );
        }
        final dy = _shiftY?.value;
        if (dy != null) {
          result = Transform.translate(
            offset: Offset(0, dy),
            child: result,
          );
        }
        return result;
      },
      child: glyphs,
    );
  }
}
