// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/motion/reduce_motion.dart';

/// Ancestor helper that lets a highlight reach tiles far down a long list.
///
/// A [SettingsHighlightTarget] only scrolls itself into view once it is
/// mounted, and lazily built rows (e.g. [ListView.builder]) past the viewport
/// plus cache extent never mount on their own. Screens wrap their scroll view
/// in this scope; every target registers its id here, and when the page opens
/// with a highlight id that isn't mounted yet, the first mounted non-target
/// steps its [Scrollable] toward the end — about one viewport per frame —
/// until the target mounts (its own highlight then takes over via
/// [Scrollable.ensureVisible]) or the end of the scrollable is reached.
///
/// [highlightId] overrides the route query lookup; when null the scope reads
/// the `highlight` query parameter like the targets do. Screens pass neither:
/// they only wrap their scroll view. Tests pass [highlightId] to drive the
/// highlight without a router.
class SettingsHighlightScope extends StatefulWidget {
  const SettingsHighlightScope({
    super.key,
    this.highlightId,
    required this.child,
  });

  final String? highlightId;
  final Widget child;

  @override
  State<SettingsHighlightScope> createState() => SettingsHighlightScopeState();

  static SettingsHighlightScopeState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_HighlightScopeBinding>()
      ?.state;
}

class SettingsHighlightScopeState extends State<SettingsHighlightScope> {
  final Set<String> _mountedIds = {};

  /// Highlight ids already delivered during this page visit: the target was
  /// reached and its pulse started. Delivery is sticky for the visit — a row
  /// that unmounts (scrolled out of the lazy list) and remounts must not
  /// treat the unchanged id as pending again, or newly mounted rows start
  /// seeking and yank the list back to the end.
  final Set<String> _deliveredIds = {};
  Object? _seeker;
  String? _queryId;
  String? _lastHighlightId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _queryId = GoRouter.maybeOf(
      context,
    )?.state.uri.queryParameters['highlight'];
    _dropStaleDelivery();
  }

  @override
  void didUpdateWidget(SettingsHighlightScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dropStaleDelivery();
  }

  void _dropStaleDelivery() {
    final current = highlightId;
    if (current != _lastHighlightId) {
      _lastHighlightId = current;
      _deliveredIds.clear();
    }
  }

  String? get highlightId => widget.highlightId ?? _queryId;

  bool isMounted(String id) => _mountedIds.contains(id);

  /// True once the highlight for [id] has been delivered this page visit.
  bool isDelivered(String id) => _deliveredIds.contains(id);

  /// Records that the highlight for [id] reached its target and started
  /// pulsing. Afterwards no row may seek or highlight again for [id] until
  /// the highlight id changes.
  void markDelivered(String id) {
    _deliveredIds.add(id);
  }

  void register(String id) => _mountedIds.add(id);

  void unregister(String id) => _mountedIds.remove(id);

  /// First mounted non-target to call this drives the seek. The winner holds
  /// it until the seek ends or it unmounts ([releaseSeek]), so scrolling one
  /// claimer off the list hands the job to a newly mounted row instead of
  /// stalling with the claim consumed.
  bool claimSeek(Object seeker) {
    if (_seeker != null) return false;
    _seeker = seeker;
    return true;
  }

  void releaseSeek(Object seeker) {
    if (identical(_seeker, seeker)) _seeker = null;
  }

  @override
  Widget build(BuildContext context) =>
      _HighlightScopeBinding(state: this, child: widget.child);
}

class _HighlightScopeBinding extends InheritedWidget {
  const _HighlightScopeBinding({required this.state, required super.child});

  final SettingsHighlightScopeState state;

  @override
  bool updateShouldNotify(_HighlightScopeBinding oldWidget) =>
      state != oldWidget.state;
}

/// Wraps a settings tile so opening its page with `?highlight=<id>` scrolls
/// the tile into view and pulses it. Pages opened normally (no id, or a
/// different id) render the child untouched.
///
/// The highlighted row gets [ColorScheme.primary] at 18% alpha plus a 3 px
/// [ColorScheme.primary] bar on its left edge. The bar is painted inside the
/// row's bounds (a [BoxDecoration] left border), so the content never moves.
/// Timing follows Komikku's `BasePreferenceWidget`: after the first frame the
/// target centres itself, waits 600 ms, then pulses 5 times at 200 ms each
/// way. The bar stays at full opacity while the tint pulses; the final
/// pulse-out fades both together over 200 ms — about 3 s total. With reduced
/// motion (OS flag or the app's own setting, both visible through
/// [ReduceMotionContext.reduceMotion]) there is no pulse: a steady tint + bar
/// shows for ~2 s, then fades jointly.
///
/// Far-down targets in lazily built lists need a [SettingsHighlightScope]
/// above the scroll view (see its docs); without one, only mounted targets
/// highlight, as before.
///
/// [activeId] overrides the scope and route query lookups; screens never pass
/// it, tests use it to drive the highlight without a router.
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
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  bool _armed = false;
  bool _seekArmed = false;
  bool _seeking = false;
  bool _done = true;
  bool _cancelled = false;
  SettingsHighlightScopeState? _scope;

  @override
  void dispose() {
    _cancelled = true;
    if (_seeking) {
      _seeking = false;
      _scope?.releaseSeek(this);
    }
    _scope?.unregister(widget.id);
    _pulse.dispose();
    _fade.dispose();
    super.dispose();
  }

  bool _isTarget(BuildContext context) {
    if (widget.activeId != null) return widget.activeId == widget.id;
    final highlight =
        _scope?.highlightId ??
        GoRouter.maybeOf(context)?.state.uri.queryParameters['highlight'];
    return highlight != null && highlight == widget.id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = SettingsHighlightScope.maybeOf(context);
    _scope?.register(widget.id);
    if (_armed) return;
    if (_isTarget(context)) {
      if (_scope?.isDelivered(widget.id) ?? false) return;
      _armed = true;
      _done = false;
      _fade.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
      return;
    }
    final pending = _scope?.highlightId;
    if (!_seekArmed && pending != null && pending != widget.id) {
      if (_scope!.isDelivered(pending)) return;
      _seekArmed = true;
      final scope = _scope!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSeek(scope));
    }
  }

  /// Steps the enclosing scrollable toward the end until the pending target
  /// mounts, so lazily built rows far down the list still get highlighted.
  /// Only one mounted target seeks per page ([SettingsHighlightScopeState.claimSeek]);
  /// the target's own [_run] takes over once it mounts.
  Future<void> _maybeSeek(SettingsHighlightScopeState scope) async {
    final pending = scope.highlightId;
    if (pending == null || _cancelled || !mounted) return;
    if (scope.isDelivered(pending) || scope.isMounted(pending)) return;
    if (!scope.claimSeek(this)) return;
    _seeking = true;
    try {
      while (!_cancelled &&
          mounted &&
          !scope.isDelivered(pending) &&
          !scope.isMounted(pending)) {
        final position = Scrollable.maybeOf(context)?.position;
        if (position == null || !position.hasPixels) return;
        if (!position.hasContentDimensions ||
            position.pixels >= position.maxScrollExtent) {
          return;
        }
        final step = position.viewportDimension;
        if (step <= 0) return;
        position.jumpTo(
          (position.pixels + step).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
    } finally {
      _seeking = false;
      scope.releaseSeek(this);
    }
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
    _scope?.markDelivered(widget.id);
    if (reduceMotion) {
      _pulse.value = 1;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_cancelled || !mounted) return;
      await Future.wait([_pulse.animateTo(0), _fade.animateTo(0)]);
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      for (var i = 0; i < 5; i++) {
        if (_cancelled || !mounted) return;
        await _pulse.forward();
        if (_cancelled || !mounted) return;
        if (i == 4) {
          await Future.wait([_pulse.reverse(), _fade.animateTo(0)]);
        } else {
          await _pulse.reverse();
        }
      }
    }
    if (_cancelled || !mounted) return;
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _fade]),
      builder: (context, child) {
        final primary = context.colorScheme.primary;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.18 * _pulse.value),
            border: Border(
              left: BorderSide(
                color: primary.withValues(alpha: _fade.value),
                width: 3,
              ),
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
