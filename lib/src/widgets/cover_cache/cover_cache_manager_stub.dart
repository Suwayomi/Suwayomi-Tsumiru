// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Web build: the browser's HTTP cache does this job, so covers share the
/// default manager instead of a filesystem-backed store.
CacheManager createCoverCacheManager() => DefaultCacheManager();
