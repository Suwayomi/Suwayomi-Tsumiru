// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Track pointers locally: recognizers receive downs before Listener; reject multi-touch and zoomed drags.

import 'package:flutter/gestures.dart';

class SingleTouchHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  SingleTouchHorizontalDragGestureRecognizer({
    super.debugOwner,
    this.isZoomedIn,
  });

  bool Function()? isZoomedIn;
  final Set<int> _selfTracked = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (isZoomedIn?.call() ?? false) {
      resolve(GestureDisposition.rejected);
      return;
    }
    if (_selfTracked.isNotEmpty) {
      _selfTracked.clear();
      resolve(GestureDisposition.rejected);
      return;
    }
    _selfTracked.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _selfTracked.remove(pointer);
    super.didStopTrackingLastPointer(pointer);
  }
}

class SingleTouchVerticalDragGestureRecognizer
    extends VerticalDragGestureRecognizer {
  SingleTouchVerticalDragGestureRecognizer({
    super.debugOwner,
    this.isZoomedIn,
  });

  bool Function()? isZoomedIn;
  final Set<int> _selfTracked = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (isZoomedIn?.call() ?? false) {
      resolve(GestureDisposition.rejected);
      return;
    }
    if (_selfTracked.isNotEmpty) {
      _selfTracked.clear();
      resolve(GestureDisposition.rejected);
      return;
    }
    _selfTracked.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _selfTracked.remove(pointer);
    super.didStopTrackingLastPointer(pointer);
  }
}

class SingleTouchPanGestureRecognizer extends PanGestureRecognizer {
  SingleTouchPanGestureRecognizer({
    super.debugOwner,
    this.isZoomedIn,
  });

  bool Function()? isZoomedIn;
  final Set<int> _selfTracked = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (isZoomedIn?.call() ?? false) {
      resolve(GestureDisposition.rejected);
      return;
    }
    if (_selfTracked.isNotEmpty) {
      _selfTracked.clear();
      resolve(GestureDisposition.rejected);
      return;
    }
    _selfTracked.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _selfTracked.remove(pointer);
    super.didStopTrackingLastPointer(pointer);
  }
}
