// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// Int slider that previews while dragging and commits once on release — for
/// prefs whose write triggers expensive work (e.g. a long-strip relayout).
class DeferredIntSliderTile extends StatefulWidget {
  const DeferredIntSliderTile({
    super.key,
    this.title,
    this.trailing,
    this.enabled = true,
    this.step = 1,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommitted,
  }) : assert((max - min) % step == 0,
            'range must land _snap and divisions on the same grid');

  final String? title;

  /// Rendered at the end of the title row (e.g. a unit switch).
  final Widget? trailing;
  final bool enabled;

  /// Snap interval; (max - min) must be a multiple of it.
  final int step;
  final String Function(int) valueLabel;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onCommitted;

  @override
  State<DeferredIntSliderTile> createState() => _DeferredIntSliderTileState();
}

class _DeferredIntSliderTileState extends State<DeferredIntSliderTile> {
  int? _dragValue;

  // A drag can outlive the range/enabled state it started under (hold the
  // thumb, tap a unit chip with the other hand) — stale bounds would trip
  // the Slider's assert or freeze the readout.
  @override
  void didUpdateWidget(DeferredIntSliderTile old) {
    super.didUpdateWidget(old);
    if (old.min != widget.min ||
        old.max != widget.max ||
        old.enabled != widget.enabled) {
      _dragValue = null;
    }
  }

  int _snap(double raw) =>
      ((raw - widget.min) / widget.step).round() * widget.step + widget.min;

  @override
  Widget build(BuildContext context) {
    final value = _dragValue ?? widget.value;
    return ListTile(
      enabled: widget.enabled,
      title: widget.title == null && widget.trailing == null
          ? null
          : Row(
              children: [
                if (widget.title != null) Expanded(child: Text(widget.title!)),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
      subtitle: Row(
        children: [
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: widget.min.toDouble(),
              max: widget.max.toDouble(),
              divisions: (widget.max - widget.min) ~/ widget.step,
              label: widget.valueLabel(value),
              onChanged: widget.enabled
                  ? (v) => setState(() => _dragValue = _snap(v))
                  : null,
              onChangeEnd: widget.enabled
                  ? (v) {
                      widget.onCommitted(_snap(v));
                      setState(() => _dragValue = null);
                    }
                  : null,
            ),
          ),
          Text(widget.valueLabel(value)),
        ],
      ),
    );
  }
}
