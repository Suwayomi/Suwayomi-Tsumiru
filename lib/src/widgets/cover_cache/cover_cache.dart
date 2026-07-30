// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'cover_cache_manager_stub.dart'
    if (dart.library.io) 'cover_cache_manager_io.dart';

part 'cover_cache.g.dart';

/// The durable cover/icon cache. keepAlive: one instance per app — cache
/// managers own an open index and a file dir; churning them leaks both.
@Riverpod(keepAlive: true)
CacheManager coverCacheManager(Ref ref) => createCoverCacheManager();

/// Whether [path] is a cover or icon — small, long-lived images that must
/// survive offline — as opposed to a chapter page. Covers route to
/// [coverCacheManager]; everything else stays on the default manager.
bool isCoverImagePath(String path) =>
    path.contains('/thumbnail') || path.contains('/extension/icon/');
