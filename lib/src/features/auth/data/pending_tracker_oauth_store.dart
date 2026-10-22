// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'pending_tracker_oauth_store_stub.dart'
    if (dart.library.io) 'pending_tracker_oauth_store_io.dart'
    as platform;

abstract interface class PendingTrackerOAuthStore {
  Future<String?> read();
  Future<bool> replace(String payload);
  Future<bool> clearIfNonce(String nonce);
  Future<bool> claim(String expectedPayload);
  Future<bool> cancel();
}

final pendingTrackerOAuthStoreProvider = Provider<PendingTrackerOAuthStore>(
  (ref) => platform.createPendingTrackerOAuthStore(),
);
