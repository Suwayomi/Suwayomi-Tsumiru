// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/painting.dart';

/// Memory-pressure clears retain floorBytes of decoded images for warm app resumes.
class SoftClearImageCache extends ImageCache {
  SoftClearImageCache({required this.floorBytes});

  final int floorBytes;

  // Keep in-flight loads; cancelling visible covers would immediately request them again.
  @override
  void clear() {
    final budget = maximumSizeBytes;
    if (budget <= floorBytes) {
      super.clear();
      return;
    }
    // Lowering the budget evicts LRU entries; restoring it retains survivors.
    maximumSizeBytes = floorBytes;
    maximumSizeBytes = budget;
  }
}
