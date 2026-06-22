// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'offline_bootstrap_stub.dart'
    if (dart.library.io) 'offline_bootstrap_io.dart' as platform;
import 'offline_database.dart';
import 'offline_page_store.dart';
import 'offline_paths.dart';

/// Open the on-device offline catalog at app startup.
///
/// Returns `null` on web (offline disabled there); on mobile/desktop returns the
/// drift database, path resolver, and page store, which `main()` uses to
/// override `offlineDatabaseProvider` / `offlinePathsProvider` /
/// `offlinePageStoreProvider`.
Future<({OfflineDatabase db, OfflinePaths paths, OfflinePageStore store})?>
    initOfflineStorage() => platform.openOfflineStorage();
