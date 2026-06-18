// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports its child's laid-out size via [onChange] after every layout in which
/// the size changed. Used by the webtoon reader to record each page image's
/// true rendered height, so a page re-entering the viewport (after being
/// disposed on a long backward scroll) can reserve that height immediately
/// instead of collapsing to a small placeholder and snapping the scroll.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onChange, required Widget child})
      : super(child: child);

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _MeasureSizeRenderObject).onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_oldSize == newSize) return;
    _oldSize = newSize;
    // Defer out of the layout phase — onChange mutates a cache the list reads.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
  }
}
