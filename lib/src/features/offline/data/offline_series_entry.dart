// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'offline_database.dart';

// A nominal class hides drift field types from provider signatures until drift generation finishes.
class OfflineSeriesEntry {
  const OfflineSeriesEntry({
    required this.manga,
    required this.downloaded,
    required this.inFlight,
    required this.bytes,
    this.failed = 0,
  });

  final OfflineManga manga;
  final int downloaded;
  final int inFlight;
  final int bytes;
  final int failed;
}
