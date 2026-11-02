// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:web/web.dart' as web;

import 'pending_tracker_oauth_store.dart';

PendingTrackerOAuthStore createPendingTrackerOAuthStore() =>
    _WebPendingTrackerOAuthStore();

class _WebPendingTrackerOAuthStore implements PendingTrackerOAuthStore {
  static const _key = 'tsumiru.pendingTrackerOAuth';

  @override
  Future<String?> read() async {
    try {
      return web.window.localStorage.getItem(_key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> replace(String payload) async {
    try {
      web.window.localStorage.setItem(_key, payload);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> claim(String expectedPayload) async {
    try {
      final storage = web.window.localStorage;
      if (storage.getItem(_key) != expectedPayload) return false;
      storage.removeItem(_key);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> clearIfNonce(String nonce) async {
    try {
      final storage = web.window.localStorage;
      final payload = storage.getItem(_key);
      if (payload == null) return false;
      final decoded = jsonDecode(payload);
      if (decoded is! Map || decoded['nonce'] != nonce) return false;
      storage.removeItem(_key);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> cancel() async {
    try {
      web.window.localStorage.removeItem(_key);
      return true;
    } catch (_) {
      return false;
    }
  }
}
