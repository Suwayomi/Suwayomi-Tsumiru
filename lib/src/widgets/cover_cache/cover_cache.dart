// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../constants/enum.dart';
import '../../features/auth/data/auth_credentials_store.dart';

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

/// The durable cover/icon cache. keepAlive: one instance per app — cache
/// managers own an open index and a file dir; churning them leaks both.
@Riverpod(keepAlive: true)
CacheManager coverCacheManager(Ref ref) => createCoverCacheManager();

/// Whether [path] is a cover or icon — small, long-lived images that must
/// survive offline — as opposed to a chapter page. Covers route to
/// [coverCacheManager]; everything else stays on the default manager.
bool isCoverImagePath(String path) =>
    path.contains('/thumbnail') || path.contains('/extension/icon/');
