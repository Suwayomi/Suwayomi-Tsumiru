// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../constants/endpoints.dart';
import '../../constants/enum.dart';
import '../../features/auth/data/auth_credentials_store.dart';
import '../../features/settings/presentation/server/widget/client/server_port_tile/server_port_tile.dart';
import '../../features/settings/presentation/server/widget/client/server_url_tile/server_url_tile.dart';

import 'cover_cache_manager_stub.dart'
    if (dart.library.io) 'cover_cache_manager_io.dart';

part 'cover_cache.g.dart';

final _imageCacheSessions = Expando<String>();

String accountImageCacheKey(
  String url, {
  required AuthType? authType,
  required AuthCredentialsStore store,
  required AuthCredentialsState? credentials,
}) {
  if (authType != AuthType.uiLogin) return url;
  final uri = Uri.tryParse(url);
  if (uri != null && uri.queryParameters.containsKey('token')) {
    final query = Map<String, dynamic>.from(uri.queryParametersAll)
      ..remove('token');
    url = uri.replace(queryParameters: query).toString();
    if (query.isEmpty) url = url.replaceFirst('?', '');
  }
  final binding = credentials?.accountBinding;
  if (!store.sessionChanging && binding != null) {
    return 'tsumiru-image:account:${Uri.encodeComponent(binding.catalogId)}/$url';
  }
  final session = _imageCacheSessions[store] ??= const Uuid().v4();
  return 'tsumiru-image:session:$session:${store.sessionEpoch}/$url';
}

/// Native covers retain a durable cache. Web images share a memory cache
/// replaced on endpoint changes so credentials follow the current origin.
@Riverpod(keepAlive: true)
CacheManager coverCacheManager(Ref ref) {
  if (!kIsWeb) return createCoverCacheManager();
  final serverUrl = Endpoints.baseApi(
    baseUrl: ref.watch(serverUrlProvider),
    port: ref.watch(serverPortProvider),
    addPort: ref.watch(serverPortToggleProvider) ?? false,
    appendApiToUrl: false,
  );
  final uri = Uri.tryParse(serverUrl);
  final hasHttpOrigin =
      uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
  final manager = createCoverCacheManager(
    serverOrigin: hasHttpOrigin ? uri.origin : null,
  );
  ref.onDispose(manager.dispose);
  return manager;
}

final serverPageCacheManagerProvider = Provider<CacheManager>(
  (ref) =>
      kIsWeb ? ref.watch(coverCacheManagerProvider) : DefaultCacheManager(),
);

/// Native covers and icons use durable storage separate from chapter pages.
bool isCoverImagePath(String path) =>
    path.contains('/thumbnail') || path.contains('/extension/icon/');
