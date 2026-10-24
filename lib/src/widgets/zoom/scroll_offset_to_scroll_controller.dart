// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Requires the position getter in yakagami's scrollable_positioned_list fork; see pubspec.

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ScrollOffsetToScrollController extends ScrollController {
  ScrollOffsetToScrollController({required this.scrollOffsetController});

  final ScrollOffsetController scrollOffsetController;

  @override
  ScrollPosition get position => scrollOffsetController.position;

  @override
  void jumpTo(double value) {
    scrollOffsetController.position.jumpTo(value);
  }

  @override
  Future<void> animateTo(
    double offset, {
    required Curve curve,
    required Duration duration,
  }) {
    // animateScroll takes a relative offset; ScrollController.animateTo takes an absolute target.
    final delta = offset - scrollOffsetController.position.pixels;
    return scrollOffsetController.animateScroll(
      offset: delta,
      duration: duration,
      curve: curve,
    );
  }
}
