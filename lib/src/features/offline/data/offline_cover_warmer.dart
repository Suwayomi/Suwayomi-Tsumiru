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
import '../../auth/data/custom_headers_store.dart';
import '../../manga_book/domain/manga/manga_model.dart';
import '../../settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../settings/presentation/server/widget/credential_popup/credentials_popup.dart';

part 'offline_cover_warmer.g.dart';

// Keep alive: background warming outlives the auto-disposed library providers that trigger it.
@Riverpod(keepAlive: true)
class OfflineCoverWarmer extends _$OfflineCoverWarmer {
  static const _concurrency = 4;

  final _inFlight = <String>{};

  @override
  void build() {}

  Future<void> warmLibraryCovers(List<MangaDto> mangas) async {
    if (kIsWeb) return;
    final auth = ref.read(authCredentialsStoreProvider.notifier);
    final epoch = auth.sessionEpoch;
    bool current() =>
        ref.mounted && !auth.sessionChanging && auth.sessionEpoch == epoch;
    if (!current()) return;
    final baseUrl = ref.read(serverUrlProvider);
    final port = ref.read(serverPortProvider);
    final addPort = ref.read(serverPortToggleProvider).ifNull();
    final manager = ref.read(coverCacheManagerProvider);

    final authType = ref.read(authTypeKeyProvider);
    final credentials = ref.read(authCredentialsStoreProvider).value;
    final pending = <({String url, String cacheKey, bool external})>[];
    for (final manga in mangas) {
      final thumb = manga.displayCoverUrl;
      if (thumb.isBlank) continue;
      final url = serverFileUrl(
        path: thumb,
        baseUrl: baseUrl,
        port: port,
        addPort: addPort,
        appendApiToUrl: false,
      );
      if (url.isEmpty) continue;
      // External covers cache under their own URL, like their widgets do.
      final external = isExternalImageUrl(
        imageUrl: thumb,
        baseUrl: baseUrl,
        port: port,
        addPort: addPort,
      );
      final serverCacheKey = accountImageCacheKey(
        url,
        authType: authType,
        store: auth,
        credentials: credentials,
      );
      final cacheKey = external ? url : serverCacheKey;
      if (_inFlight.contains(cacheKey)) continue;
      pending.add((url: url, cacheKey: cacheKey, external: external));
    }

    Future<void> warmOne(
      ({String url, String cacheKey, bool external}) request,
    ) async {
      final cacheKey = request.cacheKey;
      if (!current() || !_inFlight.add(cacheKey)) return;
      try {
        final cached = await manager.getFileFromCache(cacheKey);
        if (!current() || cached != null) return;
        // External covers carry no server credentials; the null auth type
        // below keeps every header branch empty and the token unset.
        final authType = request.external
            ? null
            : ref.read(authTypeKeyProvider);
        final basicToken = request.external
            ? null
            : ref.read(credentialsProvider).value;
        final creds = request.external
            ? null
            : ref.read(authCredentialsStoreProvider).value;
        Map<String, String>? headers;
        if (authType == AuthType.basic && basicToken != null) {
          headers = {"Authorization": basicToken};
        } else if (authType == AuthType.simpleLogin) {
          headers = creds?.simpleLoginCookieHeader;
        }
        final serverCustomHeaders =
            ref.read(customHttpHeadersProvider).value ?? const {};
        final customHeaders = request.external
            ? const <String, String>{}
            : serverCustomHeaders;
        if (customHeaders.isNotEmpty) {
          headers = applyCustomHeaders(
            Map<String, String>.from(headers ?? const {}),
            customHeaders,
          );
        }
        final uiToken = authType == AuthType.uiLogin
            ? creds?.uiAccessToken
            : null;
        headers = withUiLoginImageAuth(headers, uiToken);
        final fetchUrl = uiLoginImageUrl(request.url, uiToken);
        await manager.downloadFile(
          fetchUrl,
          key: cacheKey,
          authHeaders: headers,
        );
      } catch (_) {
      } finally {
        _inFlight.remove(cacheKey);
      }
    }

    for (var i = 0; i < pending.length; i += _concurrency) {
      if (!current()) return;
      final batch = pending.skip(i).take(_concurrency);
      await Future.wait(batch.map(warmOne));
    }
  }
}
