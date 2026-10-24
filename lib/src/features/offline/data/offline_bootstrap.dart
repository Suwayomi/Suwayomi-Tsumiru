// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'account_storage_recovery.dart';

import 'offline_bootstrap_stub.dart'
    if (dart.library.io) 'offline_bootstrap_io.dart'
    as platform;
import 'offline_database.dart';
import 'offline_page_store.dart';
import 'offline_paths.dart';

/// Null on web; native results supply the offline provider overrides.
Future<({OfflineDatabase db, OfflinePaths paths, OfflinePageStore store})?>
initOfflineStorage({
  String? accountId,
  String? legacyInstanceId,
  String? ownedRoot,
  String? accountOwner,
  AccountStorageRecovery? recovery,
}) => platform.openOfflineStorage(
  accountId: accountId,
  legacyInstanceId: legacyInstanceId,
  ownedRoot: ownedRoot,
  accountOwner: accountOwner,
  recovery: recovery,
);

Future<bool> accountStorageWasCleared(OfflinePaths paths) =>
    platform.accountStorageWasCleared(paths);
