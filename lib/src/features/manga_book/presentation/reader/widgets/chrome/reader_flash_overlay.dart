// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../../../constants/db_keys.dart';
import '../../../../../../constants/enum.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../settings/presentation/reader/widgets/reader_general_prefs/reader_general_prefs.dart';

/// "Flash on page change" (Komikku DisplayRefreshHost): every Nth page change
/// paints a full-screen color for flashDuration×100 ms. whiteBlack shows white
/// for the first half, black for the second — all within one flash.
///
/// Pure chrome leaf: listens to [currentIndex] rebuilds only, never touches
/// the (frozen) viewer engines.
class ReaderFlashOverlay extends HookConsumerWidget {
  const ReaderFlashOverlay({super.key, required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(flashOnPageChangeProvider).ifNull(false);
    final durationTicks = ref.watch(flashDurationProvider) ??
        DBKeys.flashDuration.initial as int;
    final interval = ref.watch(flashPageIntervalProvider) ??
        DBKeys.flashPageInterval.initial as int;
    final flashColor = ref.watch(flashColorKeyProvider) ??
        DBKeys.flashColor.initial as FlashColor;

    final color = useState<Color?>(null);
    final prevIndex = useRef<int?>(null);
    // Komikku counts from 0, so the first qualifying change always flashes.
    final timesCalled = useRef(0);
    final halfTimer = useRef<Timer?>(null);
    final endTimer = useRef<Timer?>(null);

    useEffect(
      () => () {
        halfTimer.value?.cancel();
        endTimer.value?.cancel();
      },
      const [],
    );

    useEffect(() {
      final prev = prevIndex.value;
      prevIndex.value = currentIndex;
      // Initial mount isn't a page change.
      if (!enabled || prev == null || prev == currentIndex) return null;
      final flashNow = timesCalled.value % interval.clamp(1, 10) == 0;
      timesCalled.value++;
      if (!flashNow) return null;

      halfTimer.value?.cancel();
      endTimer.value?.cancel();
      color.value =
          flashColor == FlashColor.black ? Colors.black : Colors.white;
      final half =
          Duration(milliseconds: durationTicks * kFlashMsPerTick ~/ 2);
      if (flashColor == FlashColor.whiteBlack) {
        halfTimer.value = Timer(half, () => color.value = Colors.black);
      }
      endTimer.value = Timer(half * 2, () => color.value = null);
      return null;
    }, [currentIndex]);

    if (color.value == null) return const SizedBox.shrink();
    return IgnorePointer(child: ColoredBox(color: color.value!));
  }
}
