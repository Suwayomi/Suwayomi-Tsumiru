// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'graphql_cache_guard_stub.dart'
    if (dart.library.io) 'graphql_cache_guard_io.dart' as platform;

/// Delete the legacy on-disk GraphQL cache box, returning its size in bytes
/// (null when absent). The cache is in-memory now (the default fetch policy is
/// noCache, so persisting it was write-only bloat); older installs carry a box
/// file of unbounded size — up to GBs — whose whole-file load OOM-crashed
/// startup.
Future<int?> deleteLegacyGraphqlCacheBox() =>
    platform.deleteLegacyGraphqlCacheBox();
