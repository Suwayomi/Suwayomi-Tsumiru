// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'pending_tracker_oauth_store.dart';

PendingTrackerOAuthStore createPendingTrackerOAuthStore() => _Unavailable();

class _Unavailable implements PendingTrackerOAuthStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<bool> replace(String payload) async => false;
  @override
  Future<bool> clearIfNonce(String nonce) async => false;
  @override
  Future<bool> claim(String expectedPayload) async => false;
  @override
  Future<bool> cancel() async => true;
}
