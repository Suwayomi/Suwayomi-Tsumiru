// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'offline_database.dart';

/// One Downloads → On device row. A nominal class (not a record) on purpose:
/// a record type inlines drift's generated OfflineManga into the provider
/// signature, which riverpod_generator can't resolve in its build phase.
/// Member types are never emitted, so the drift row is fine as a field.
class OfflineSeriesEntry {
  const OfflineSeriesEntry({
    required this.manga,
    required this.downloaded,
    required this.inFlight,
    required this.bytes,
  });

  final OfflineManga manga;
  final int downloaded;
  final int inFlight;
  final int bytes;
}
