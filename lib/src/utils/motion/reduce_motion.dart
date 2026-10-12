// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reduce_motion.g.dart';

/// App-requested reduced motion, in addition to the OS "Remove animations" flag.
@riverpod
class AppReduceMotion extends _$AppReduceMotion {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

extension ReduceMotionContext on BuildContext {
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);

  /// Flutter's own off switch for dialogs, sheets, menus and snackbars.
  AnimationStyle? get motionStyle =>
      reduceMotion ? AnimationStyle.noAnimation : null;

  /// Not zero: a zero-length snackbar re-enters Flutter's queue at once.
  AnimationStyle? get snackBarMotionStyle => reduceMotion
      ? const AnimationStyle(
          duration: Duration(milliseconds: 1),
          reverseDuration: Duration(milliseconds: 1),
        )
      : null;
}

/// Merges the OS flag with [appReduceMotionProvider] into [MediaQuery] and
/// [Theme]. Always mounted, so toggling the flag never remounts the subtree.
class ReduceMotionScope extends ConsumerWidget {
  const ReduceMotionScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        ref.watch(appReduceMotionProvider);
    final theme = Theme.of(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: Theme(data: reduce ? _reducedTheme(theme) : theme, child: child),
    );
  }
}

ThemeData _reducedTheme(ThemeData theme) => theme.copyWith(
  pageTransitionsTheme: PageTransitionsTheme(
    builders: {
      for (final platform in TargetPlatform.values)
        platform: const _NoPageTransitionBuilder(),
    },
  ),
  splashFactory: NoSplash.splashFactory,
  expansionTileTheme: theme.expansionTileTheme.copyWith(
    expansionAnimationStyle: AnimationStyle.noAnimation,
  ),
);

class _NoPageTransitionBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => ReducedRouteTransition(animation: animation, child: child);
}

/// Keeps a route's page mounted but unpainted while the route pops, so the
/// page underneath shows at once instead of after the 300 ms reverse.
class ReducedRouteTransition extends StatelessWidget {
  const ReducedRouteTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: animation,
      builder: (context, child) => Visibility(
        visible: animation.status != AnimationStatus.reverse,
        maintainState: true,
        maintainAnimation: true,
        child: child!,
      ),
      child: child,
    );
  }
}
