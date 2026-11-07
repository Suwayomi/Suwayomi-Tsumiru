// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../utils/extensions/custom_extensions.dart';

/// How a screen wants [SideInsetSafeArea] to treat the side insets.
@immutable
class SideInsetStyle {
  const SideInsetStyle({this.fill, this.drawUnder = false});

  /// Colour of the inset; the theme's scaffold colour when null.
  final Color? fill;

  /// Leave the insets to the screen, which draws under them and applies them
  /// itself (a reader that ignores the safe area).
  final bool drawUnder;

  @override
  bool operator ==(Object other) =>
      other is SideInsetStyle &&
      other.fill == fill &&
      other.drawUnder == drawUnder;

  @override
  int get hashCode => Object.hash(fill, drawUnder);
}

/// Keeps compact layouts out of side insets.
///
/// iPhone Duo's outer display is a compact portrait window with the status
/// bar and camera in a full-height column at its side, reported as
/// `MediaQuery.padding.right`. Widgets that set their own padding (grids,
/// most list and detail pages) drop MediaQuery's side insets, so their content
/// ran under that column. Other phones report no side insets in compact
/// windows, and medium and wider layouts already apply [SafeArea] in the
/// navigation shell, so this only changes anything where a compact window has
/// side insets.
///
/// A screen can change the inset's colour or take the insets over with
/// [SideInsetStyler].
///
/// The tree has the same shape whether or not the insets apply, so rotating
/// between compact and medium does not remount [child].
class SideInsetSafeArea extends StatefulWidget {
  const SideInsetSafeArea({super.key, required this.child});

  final Widget child;

  @override
  State<SideInsetSafeArea> createState() => _SideInsetSafeAreaState();
}

class _SideInsetSafeAreaState extends State<SideInsetSafeArea> {
  // Insertion ordered: the most recently mounted screen wins, and a screen
  // that updates its style keeps its place.
  final _styles = <Object, SideInsetStyle>{};

  SideInsetStyle? get _current => _styles.isEmpty ? null : _styles.values.last;

  void _put(Object owner, SideInsetStyle? style) {
    if (!mounted) return;
    final before = _current;
    if (style == null) {
      _styles.remove(owner);
    } else {
      _styles[owner] = style;
    }
    if (_current != before) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final style = _current;
    final padding = MediaQuery.paddingOf(context);
    final apply =
        context.windowSizeClass == WindowSizeClass.compact &&
        !(style?.drawUnder ?? false);
    final left = apply ? padding.left : 0.0;
    final right = apply ? padding.right : 0.0;
    return _SideInsetScope(
      state: this,
      child: ColoredBox(
        // Fills the inset with the page colour, not the bare window.
        color: style?.fill ?? Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: EdgeInsets.only(left: left, right: right),
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: apply,
            removeRight: apply,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _SideInsetScope extends InheritedWidget {
  const _SideInsetScope({required this.state, required super.child});

  final _SideInsetSafeAreaState state;

  @override
  bool updateShouldNotify(_SideInsetScope oldWidget) => false;
}

/// Applies [style] to the enclosing [SideInsetSafeArea] while this widget's
/// route is shown.
///
/// The colour applies from the start of the route's entrance; drawing under
/// the insets waits until the route covers the screen, so pages below never
/// lay out under them while visible. Both end as the route starts to leave.
class SideInsetStyler extends StatefulWidget {
  const SideInsetStyler({super.key, required this.style, required this.child});

  final SideInsetStyle style;
  final Widget child;

  @override
  State<SideInsetStyler> createState() => _SideInsetStylerState();
}

class _SideInsetStylerState extends State<SideInsetStyler> {
  final _token = Object();
  _SideInsetSafeAreaState? _host;
  Animation<double>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _host = context.getInheritedWidgetOfExactType<_SideInsetScope>()?.state;
    final route = ModalRoute.of(context)?.animation;
    if (route != _route) {
      _route?.removeStatusListener(_onStatus);
      _route = route?..addStatusListener(_onStatus);
    }
    _sync();
  }

  @override
  void didUpdateWidget(SideInsetStyler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) _sync();
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onStatus);
    _post(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _onStatus(AnimationStatus _) => _sync();

  void _sync() {
    final status = _route?.status ?? AnimationStatus.completed;
    _post(switch (status) {
      AnimationStatus.reverse || AnimationStatus.dismissed => null,
      AnimationStatus.forward => SideInsetStyle(fill: widget.style.fill),
      AnimationStatus.completed => widget.style,
    });
  }

  // The host sits above the Navigator; changing it during this subtree's
  // build or unmount is not allowed, so wait until the frame is done.
  void _post(SideInsetStyle? style) {
    final host = _host;
    if (host == null) return;
    scheduleMicrotask(() => host._put(_token, style));
  }
}
