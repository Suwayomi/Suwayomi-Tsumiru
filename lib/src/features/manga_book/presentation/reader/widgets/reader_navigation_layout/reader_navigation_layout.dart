// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/app_constants.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../settings/presentation/reader/widgets/reader_navigation_layout_tile/reader_navigation_layout_tile.dart';
import '../../../../../settings/presentation/reader/widgets/reader_paged_prefs/reader_paged_prefs.dart';
import '../../../../../settings/presentation/reader/widgets/reader_tap_invert/reader_tap_invert.dart';
import 'layouts/edge_layout.dart';
import 'layouts/kindlish_layout.dart';
import 'layouts/l_shaped_layout.dart';
import 'layouts/right_and_left_layout.dart';

class ReaderNavigationLayoutWidget extends HookConsumerWidget {
  const ReaderNavigationLayoutWidget({
    super.key,
    this.navigationLayout,
    this.tapInvert,
    required this.onPrevious,
    required this.onNext,
    this.showReaderLayoutAnimation = false,
  });
  final ReaderNavigationLayout? navigationLayout;

  /// Per-series override; null falls back to the global compat value.
  final TapInvert? tapInvert;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool showReaderLayoutAnimation;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animationController = useAnimationController(duration: kLongDuration);
    useAnimation(animationController);
    final nextColorTween = ColorTween(
      begin: showReaderLayoutAnimation ? Colors.green : Colors.transparent,
    ).animate(animationController).value;

    final prevColorTween = ColorTween(
      begin: showReaderLayoutAnimation ? Colors.blue : Colors.transparent,
    ).animate(animationController).value;
    useEffect(() {
      animationController.forward();
      return;
    }, []);

    final layout = navigationLayout == null ||
            navigationLayout == ReaderNavigationLayout.defaultNavigation
        ? ref.watch(readerNavigationLayoutKeyProvider)
        : navigationLayout;
    // Axis-wise inversion: horizontal swaps the
    // left/right zones, vertical swaps the L-shaped top/bottom rows.
    final TapInvert invert =
        tapInvert ?? ref.watch(readerTapInvertCompatProvider);
    // "Smaller tap zones": shrinks the active edge regions (0.25 vs
    // 0.33 of the axis), widening the center dead-zone.
    final bool smaller = ref.watch(smallerTapZonesProvider) ?? false;
    final invertH = invert.invertsHorizontal;
    final invertV = invert.invertsVertical;
    final onLeftTap = invertH ? onNext : onPrevious;
    final onRightTap = invertH ? onPrevious : onNext;
    final leftColor = invertH ? nextColorTween : prevColorTween;
    final rightColor = invertH ? prevColorTween : nextColorTween;
    final onTopTap = invertV ? onNext : onPrevious;
    final onBottomTap = invertV ? onPrevious : onNext;
    final topColor = invertV ? nextColorTween : prevColorTween;
    final bottomColor = invertV ? prevColorTween : nextColorTween;
    return switch (layout) {
      ReaderNavigationLayout.edge => EdgeLayout(
          onLeftTap: onLeftTap,
          onRightTap: onRightTap,
          leftColor: leftColor,
          rightColor: rightColor,
          smaller: smaller,
        ),
      ReaderNavigationLayout.kindlish => KindlishLayout(
          onLeftTap: onLeftTap,
          onRightTap: onRightTap,
          leftColor: leftColor,
          rightColor: rightColor,
          smaller: smaller,
        ),
      ReaderNavigationLayout.lShaped => LShapedLayout(
          onLeftTap: onLeftTap,
          onRightTap: onRightTap,
          leftColor: leftColor,
          rightColor: rightColor,
          onTopTap: onTopTap,
          onBottomTap: onBottomTap,
          topColor: topColor,
          bottomColor: bottomColor,
          smaller: smaller,
        ),
      ReaderNavigationLayout.rightAndLeft => RightAndLeftLayout(
          onLeftTap: onLeftTap,
          onRightTap: onRightTap,
          leftColor: leftColor,
          rightColor: rightColor,
          smaller: smaller,
        ),
      ReaderNavigationLayout.defaultNavigation ||
      ReaderNavigationLayout.disabled ||
      null =>
        const SizedBox.shrink(),
    };
  }
}
