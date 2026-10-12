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
bool appReduceMotion(Ref ref) => false;

extension ReduceMotionContext on BuildContext {
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
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
  ) => child;
}
