// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/enum.dart';
import '../../../global_providers/global_providers.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../widgets/cover_cache/cover_cache.dart';
import '../../../widgets/server_image.dart';
import '../../auth/data/auth_credentials_store.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';

part 'offline_cover_warmer.g.dart';

/// Downloads library covers into the durable cover cache during online use.
///
/// The cover cache only holds covers the user has scrolled past; a series
/// added but never viewed would still be a broken image offline. The library
/// list already syncs the catalog on every online load, so the same pass tops
/// up missing covers — a no-op once every cover is present.
///
/// keepAlive: the warm loop outlives the (autoDispose) library providers that
/// trigger it, and reading providers from a disposed ref throws.
@Riverpod(keepAlive: true)
class OfflineCoverWarmer extends _$OfflineCoverWarmer {
  static const _concurrency = 4;

  /// Cache keys currently being fetched, so overlapping library loads don't
  /// stack duplicate downloads.
  final _inFlight = <String>{};

  @override
  void build() {}

  Future<void> warmLibraryCovers(List<MangaDto> mangas) async {
    if (kIsWeb) return;
    final baseUrl = ref.read(serverUrlProvider);
    final port = ref.read(serverPortProvider);
    final addPort = ref.read(serverPortToggleProvider).ifNull();
    final manager = ref.read(coverCacheManagerProvider);

    final pending = <String>[];
    for (final manga in mangas) {
      final thumb = manga.thumbnailUrl;
      if (thumb.isBlank) continue;
      final cacheKey = serverFileUrl(
        path: thumb!,
        baseUrl: baseUrl,
        port: port,
        addPort: addPort,
        appendApiToUrl: false,
      );
      if (cacheKey.isEmpty || _inFlight.contains(cacheKey)) continue;
      pending.add(cacheKey);
    }

    Future<void> warmOne(String cacheKey) async {
      if (!_inFlight.add(cacheKey)) return;
      try {
        final cached = await manager.getFileFromCache(cacheKey);
        if (cached != null) return;
        // Auth is read PER DOWNLOAD, not snapshotted for the run: a big
        // first-time warm outlives ui_login token rotation, and a stale
        // snapshot would 401 the whole tail of the library. This notifier is
        // keepAlive, so late ref reads are safe.
        final authType = ref.read(authTypeKeyProvider);
        final basicToken = ref.read(credentialsProvider).value;
        final creds = ref.read(authCredentialsStoreProvider).value;
        Map<String, String>? headers;
        if (authType == AuthType.basic && basicToken != null) {
          headers = {"Authorization": basicToken};
        } else if (authType == AuthType.simpleLogin) {
          headers = creds?.simpleLoginCookieHeader;
        }
        final fetchUrl = appendUiLoginToken(
          cacheKey,
          authType == AuthType.uiLogin ? creds?.uiAccessToken : null,
        );
        await manager.downloadFile(
          fetchUrl,
          key: cacheKey,
          authHeaders: headers,
        );
      } catch (_) {
        // Best-effort: a failed cover fetch retries on the next library load.
      } finally {
        _inFlight.remove(cacheKey);
      }
    }

    // Bounded fan-out so a first-time warm of a large library doesn't hammer
    // the server or saturate the connection.
    for (var i = 0; i < pending.length; i += _concurrency) {
      final batch = pending.skip(i).take(_concurrency);
      await Future.wait(batch.map(warmOne));
    }
  }
}
