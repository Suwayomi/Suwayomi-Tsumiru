// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'graphql_cache_guard_stub.dart'
    if (dart.library.io) 'graphql_cache_guard_io.dart' as platform;

/// Delete the legacy disk cache without loading it; return its byte size, or null when absent.
Future<int?> deleteLegacyGraphqlCacheBox() =>
    platform.deleteLegacyGraphqlCacheBox();
