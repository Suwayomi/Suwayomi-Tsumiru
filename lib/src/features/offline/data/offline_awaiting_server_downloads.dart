// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import 'offline_storage_identity.dart';

typedef OfflineRead = T Function<T>(ProviderListenable<T> provider);

String offlinePreferenceKey(OfflineRead read, DBKeys key) {
  final preferences = read(sharedPreferencesProvider);
  final catalog = preferences.getString(offlineCatalogServerIdKey(preferences));
  return read(authTypeKeyProvider) == AuthType.uiLogin && catalog != null
      ? '${key.name}/$catalog'
      : key.name;
}

// Every reconcile entry must register server-fetch obligations for the later device pull.
final Set<int> awaitingServerDownloads = {};

// Persist before the next drain so restart cannot lose the second-hop obligation.
Future<void> persistAwaitingServerDownloads(OfflineRead read) =>
    read(sharedPreferencesProvider).setStringList(
      offlinePreferenceKey(read, DBKeys.offlineCatchUpAwaitingPull),
      [for (final id in awaitingServerDownloads) '$id'],
    );
