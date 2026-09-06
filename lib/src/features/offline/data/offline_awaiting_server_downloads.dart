// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../global_providers/global_providers.dart';

/// Sendable read signature shared by `Ref.read`, `WidgetRef.read`, and
/// `ProviderContainer.read` — lets the functions below stay agnostic of which
/// kind of reader the caller has.
typedef OfflineRead = T Function<T>(ProviderListenable<T> provider);

/// Manga whose reconcile had to ask the SERVER to download chapters first —
/// their device pull can only happen after those finish.
///
/// Shared by EVERY reconcile entry point: the automatic keep-rule catch-up
/// pass (`offline_chapter_catchup.dart`'s `runKeepRuleCatchUp`/
/// `pullAfterServerDownloads`) and the manga-details-triggered entry points
/// (`reconcileManga`/`reconcileMangaWidget`/`reconcileMangaContainer` in
/// `offline_download_providers.dart`). Only the catch-up pass used to
/// register here — a manga-details-triggered download that needed a server
/// fetch first silently missed the progressive
/// pull-as-soon-as-the-server-queue-drains mechanism
/// (`offline_chapter_catchup.dart`'s `downloadsMapProvider` listener) and sat
/// waiting for the next full-library sync instead. Registering from every
/// entry point here closes that gap.
final Set<int> awaitingServerDownloads = {};

/// Persists the current [awaitingServerDownloads] set so a crash/restart
/// before the next drain doesn't lose the obligation.
Future<void> persistAwaitingServerDownloads(OfflineRead read) =>
    read(sharedPreferencesProvider).setStringList(
      DBKeys.offlineCatchUpAwaitingPull.name,
      [for (final id in awaitingServerDownloads) '$id'],
    );
