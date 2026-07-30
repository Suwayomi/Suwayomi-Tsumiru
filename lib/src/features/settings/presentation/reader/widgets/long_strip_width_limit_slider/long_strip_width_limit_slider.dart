// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../widgets/deferred_int_slider_tile.dart';

/// Long-strip "Maximum width" control: one always-visible slider with a
/// %-of-window / absolute-px unit switch (Houdoku model). 100% is the off
/// position; a px cap wider than the window is naturally inert.
class LongStripWidthLimitSlider extends StatelessWidget {
  const LongStripWidthLimitSlider({
    super.key,
    required this.enabled,
    required this.usePixels,
    required this.percent,
    required this.px,
    required this.onUnitChanged,
    required this.onPercentCommitted,
    required this.onPxCommitted,
  });

  final bool enabled;
  final bool usePixels;
  final int percent;
  final int px;
  final ValueChanged<bool> onUnitChanged;
  final ValueChanged<int> onPercentCommitted;
  final ValueChanged<int> onPxCommitted;

  @override
  Widget build(BuildContext context) {
    return DeferredIntSliderTile(
      title: context.l10n.longStripWidthLimit,
      enabled: enabled,
      trailing: SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: [
          ButtonSegment(
            value: false,
            label: Text(context.l10n.longStripWidthLimitUnitPercent),
          ),
          ButtonSegment(
            value: true,
            label: Text(context.l10n.longStripWidthLimitUnitPixels),
          ),
        ],
        selected: {usePixels},
        onSelectionChanged:
            enabled ? (s) => onUnitChanged(s.first) : null,
      ),
      // Clamped and snapped to the grid: an unsanitized stored pref would
      // otherwise trip the Slider's range assert or hop on first touch.
      value: usePixels
          ? ((px.clamp(200, 2000) - 200) / 50).round() * 50 + 200
          : percent.clamp(10, 100),
      min: usePixels ? 200 : 10,
      max: usePixels ? 2000 : 100,
      step: usePixels ? 50 : 1,
      valueLabel: (v) => usePixels
          ? context.l10n.longStripWidthLimitPx(v)
          : v >= 100
              ? context.l10n.longStripWidthLimitFullWidth
              : context.l10n.longStripWidthLimitPercent(v),
      onCommitted: usePixels ? onPxCommitted : onPercentCommitted,
    );
  }
}
