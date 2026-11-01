// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports changed layout size after the frame so webtoon pages can reserve their measured extent.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({
    super.key,
    this.onChange,
    this.onResize,
    required Widget child,
  }) : super(child: child);

  final ValueChanged<Size>? onChange;
  final VoidCallback? onResize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange, onResize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _MeasureSizeRenderObject)
      ..onChange = onChange
      ..onResize = onResize;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange, this.onResize);

  ValueChanged<Size>? onChange;
  VoidCallback? onResize;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_oldSize == newSize) return;
    if (_oldSize != null) onResize?.call();
    _oldSize = newSize;
    // Defer out of the layout phase — onChange mutates a cache the list reads.
    if (onChange != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange?.call(newSize));
    }
  }
}
