// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';

/// Wraps a settings tile so opening its page with `?highlight=<id>` scrolls
/// the tile into view and pulses it. Pages opened normally (no id, or a
/// different id) render the child untouched.
///
/// Timing follows Komikku's `BasePreferenceWidget`: after the first frame the
/// target centres itself, waits 600 ms, then pulses 5 times at 200 ms each
/// way before settling — about 3 s total. With reduced motion (OS flag or the
/// app's own setting, both visible through [ReduceMotionContext.reduceMotion])
/// there is no pulse: a steady tint shows for ~2 s instead.
///
/// [activeId] overrides the route query lookup; screens never pass it, tests
/// use it to drive the highlight without a router.
class SettingsHighlightTarget extends StatefulWidget {
  const SettingsHighlightTarget({
    super.key,
    required this.id,
    required this.child,
    this.activeId,
  });

  final String id;
  final Widget child;
  final String? activeId;

  @override
  State<SettingsHighlightTarget> createState() =>
      _SettingsHighlightTargetState();
}

class _SettingsHighlightTargetState extends State<SettingsHighlightTarget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  bool _armed = false;
  bool _done = true;
  bool _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    _pulse.dispose();
    super.dispose();
  }

  bool _isTarget(BuildContext context) {
    if (widget.activeId != null) return widget.activeId == widget.id;
    final highlight = GoRouter.maybeOf(
      context,
    )?.state.uri.queryParameters['highlight'];
    return highlight != null && highlight == widget.id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed || !_isTarget(context)) return;
    _armed = true;
    _done = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_cancelled || !mounted) return;
    final reduceMotion = context.reduceMotion;
    await Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 300),
    );
    if (_cancelled || !mounted) return;
    if (reduceMotion) {
      _pulse.value = 1;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_cancelled || !mounted) return;
      await _pulse.animateTo(0, duration: const Duration(milliseconds: 200));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      for (var i = 0; i < 5; i++) {
        if (_cancelled || !mounted) return;
        await _pulse.forward();
        if (_cancelled || !mounted) return;
        await _pulse.reverse();
      }
    }
    if (_cancelled || !mounted) return;
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Container(
        color: context.colorScheme.primary.withValues(
          alpha: 0.12 * _pulse.value,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
