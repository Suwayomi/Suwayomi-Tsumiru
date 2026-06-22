// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'offline_database.dart';
import 'offline_page_store.dart';
import 'offline_paths.dart';

/// Web stub: offline storage is disabled on web (no bulk file storage), so the
/// providers are never overridden and the offline UI stays hidden.
Future<({OfflineDatabase db, OfflinePaths paths, OfflinePageStore store})?>
    openOfflineStorage() async => null;
