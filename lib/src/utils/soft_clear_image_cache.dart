// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/painting.dart';

/// ImageCache whose [clear] evicts down to [floorBytes] instead of emptying.
///
/// Flutter answers every Android memory-pressure signal — including the one
/// sent for plain backgrounding — by clearing the decoded-image cache to
/// zero, so returning to the app re-decoded (and re-faded) every library
/// cover. Coil keeps a working set on that signal and only empties when the
/// app is queued to be killed. Keeping a floor is that behavior: an app
/// switch stays warm, and a genuine low-memory event still frees everything
/// above the floor.
class SoftClearImageCache extends ImageCache {
  SoftClearImageCache({required this.floorBytes});

  final int floorBytes;

  // Unlike a real clear, in-flight loads survive — deliberately: pending
  // images are covers entering the screen right now, and cancelling them
  // would only re-request the same bytes. Known cost: hot-reloaded asset
  // edits can serve stale (dev-only, and everything here is network-fetched).
  @override
  void clear() {
    final budget = maximumSizeBytes;
    if (budget <= floorBytes) {
      super.clear();
      return;
    }
    // Shrinking the budget evicts LRU entries to fit; restoring it keeps
    // the survivors.
    maximumSizeBytes = floorBytes;
    maximumSizeBytes = budget;
  }
}
