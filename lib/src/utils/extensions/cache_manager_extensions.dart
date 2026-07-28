// Copyright (c) 2023 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../constants/enum.dart';
import '../../features/auth/data/auth_credentials_store.dart';
import '../../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';
import '../../features/settings/presentation/server/widget/credential_popup/credentials_popup.dart';
import '../../global_providers/global_providers.dart';
import '../../widgets/server_image.dart';
import 'custom_extensions.dart';

extension CacheManagerExtension on CacheManager {
  /// Warms the cache for a server-relative [url] using the same URL, cache key
  /// and auth [ServerImage] would use, so the prefetched entry is the one the
  /// on-screen widget later reads.
  Future<File> getServerFile(WidgetRef ref, String url,
      {bool appendApiToUrl = true}) async {
    final authType = ref.read(authTypeKeyProvider);
    final basicToken = ref.read(credentialsProvider).value;
    final creds = ref.read(authCredentialsStoreProvider).value;

    final baseApi = serverFileUrl(
      path: url,
      baseUrl: ref.read(serverUrlProvider),
      port: ref.read(serverPortProvider),
      addPort: ref.read(serverPortToggleProvider).ifNull(),
      appendApiToUrl: appendApiToUrl,
    );
    if (baseApi.isEmpty) {
      throw ArgumentError.value(url, 'url', 'No server path to fetch');
    }

    Map<String, String>? headers;
    if (authType == AuthType.basic && basicToken != null) {
      headers = {"Authorization": basicToken};
    } else if (authType == AuthType.simpleLogin) {
      headers = creds?.simpleLoginCookieHeader;
    }

    // For ui_login, append ?token= because cached_network_image can't
    // reliably forward Authorization headers on web. Use the un-tokened
    // URL as cacheKey so token rotation doesn't bust the cache.
    final fetchUrl = appendUiLoginToken(
      baseApi,
      authType == AuthType.uiLogin ? creds?.uiAccessToken : null,
    );

    return await getSingleFile(fetchUrl, key: baseApi, headers: headers);
  }
}
