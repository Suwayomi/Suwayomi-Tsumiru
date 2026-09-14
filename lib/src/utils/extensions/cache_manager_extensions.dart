// Copyright (c) 2023 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../widgets/server_image.dart';

extension CacheManagerExtension on CacheManager {
  Future<File> getServerFile(
    WidgetRef ref,
    String url, {
    bool appendApiToUrl = true,
  }) async {
    final request = serverImageRequest(
      ref,
      url,
      appendApiToUrl: appendApiToUrl,
    );
    if (request.localPath != null) return File(request.localPath!);
    if (request.fetchUrl.isEmpty) {
      throw ArgumentError.value(url, 'url', 'No server path to fetch');
    }
    return getSingleFile(
      request.fetchUrl,
      key: request.cacheKey,
      headers: request.headers,
    );
  }
}
