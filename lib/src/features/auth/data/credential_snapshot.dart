// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/db_keys.dart';
import 'secure_credentials_provider.dart';

/// Legacy unused password key, retained only for upgrade cleanup.
const kLegacyPasswordSecureKey = 'auth.password';
const kSimpleLoginCookieSecureKey = 'auth.simple.cookie';
const kUiAccessTokenSecureKey = 'auth.ui.accessToken';
const kUiRefreshTokenSecureKey = 'auth.ui.refreshToken';
const kUiAccountBindingSecureKey = 'auth.ui.accountBinding';
const kBasicCredentialsKey = 'auth.basic.credentials';
const kCustomHeadersKey = 'custom.headers';

/// Persist the full account set; the invalidation marker flags incomplete writes.
const kCredentialKeys = <String>[
  kLegacyPasswordSecureKey,
  kSimpleLoginCookieSecureKey,
  kUiAccessTokenSecureKey,
  kUiRefreshTokenSecureKey,
  kUiAccountBindingSecureKey,
  kBasicCredentialsKey,
];

/// Endpoint keys survive account invalidation and are persisted only when changed.
const kEndpointKeys = <String>[kCustomHeadersKey];

/// True when failed persistence means disk credentials may differ from memory.
bool credentialsInvalidated(SharedPreferences prefs) =>
    prefs.getBool(DBKeys.authCredentialsInvalidated.name) ?? false;

Future<void> _markCredentialsInvalidated(SharedPreferences prefs) =>
    prefs.setBool(DBKeys.authCredentialsInvalidated.name, true);

Future<void> _clearCredentialInvalidation(SharedPreferences prefs) =>
    prefs.setBool(DBKeys.authCredentialsInvalidated.name, false);

class _SnapshotSlot {
  _SnapshotSlot(this.prefs, this.snapshot);

  final SharedPreferences prefs;
  final CredentialSnapshot snapshot;
}

final Expando<_SnapshotSlot> _snapshots = Expando('credential snapshot');

/// Shared across session containers by store identity; a new preferences instance starts a new run.
CredentialSnapshot credentialSnapshot(
  FlutterSecureStorage storage,
  SharedPreferences prefs,
) {
  final slot = _snapshots[storage];
  if (slot != null && identical(slot.prefs, prefs)) return slot.snapshot;
  return (_snapshots[storage] = _SnapshotSlot(
    prefs,
    CredentialSnapshot._(storage),
  )).snapshot;
}

/// In-memory credential authority, loaded once per run and persisted as a complete set.
class CredentialSnapshot {
  CredentialSnapshot._(this._storage);

  final FlutterSecureStorage _storage;
  final Map<String, String?> _values = {};
  Future<void>? _loading;
  Future<void> _persistTail = Future<void>.value();

  String? operator [](String key) => _values[key];

  /// Loads once; an invalidation marker starts signed out and clears only after cleanup succeeds.
  Future<void> ensureLoaded(SharedPreferences prefs) =>
      _loading ??= _load(prefs);

  Future<void> _load(SharedPreferences prefs) async {
    final invalidated = credentialsInvalidated(prefs);
    if (invalidated) {
      final deleted = await Future.wait(
        kCredentialKeys.map((key) => deleteSecure(_storage, key)),
      );
      if (deleted.every((ok) => ok)) {
        await _clearCredentialInvalidation(prefs);
      }
    } else {
      // Legacy-password cleanup is best effort and must not affect the invalidation marker.
      unawaited(deleteSecure(_storage, kLegacyPasswordSecureKey));
    }
    for (final key in [...kCredentialKeys, ...kEndpointKeys]) {
      if (key == kLegacyPasswordSecureKey) continue;
      if (invalidated && kCredentialKeys.contains(key)) continue;
      _values[key] = await readSecureOrAbsent(_storage, key);
    }
  }

  /// Updates memory, persists the complete account set, and marks partial failures as invalid.
  /// Endpoint changes are independent and never affect the marker.
  /// Returns whether the full account state reached storage.
  /// Set [invalidateOnFailure] false only when a durable legacy copy remains for migration.
  Future<bool> update(
    Map<String, String?> changes,
    SharedPreferences prefs, {
    bool invalidateOnFailure = true,
  }) {
    _values.addAll(changes);
    final target = Map<String, String?>.from(_values);
    final result = _persistTail.then(
      (_) => _persist(
        target,
        changes,
        prefs,
        invalidateOnFailure: invalidateOnFailure,
      ),
    );
    _persistTail = result.then((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<bool> _persist(
    Map<String, String?> target,
    Map<String, String?> changes,
    SharedPreferences prefs, {
    required bool invalidateOnFailure,
  }) async {
    if (!changes.keys.any(kCredentialKeys.contains)) {
      var complete = true;
      for (final key in kEndpointKeys) {
        if (!changes.containsKey(key)) continue;
        final value = target[key];
        final saved = value == null
            ? await deleteSecure(_storage, key)
            : await writeSecure(_storage, key, value);
        if (!saved) complete = false;
      }
      return complete;
    }
    var complete = true;
    for (final key in kCredentialKeys) {
      final value = target[key];
      if (value == null) continue;
      if (!await writeSecure(_storage, key, value)) complete = false;
    }
    for (final key in kCredentialKeys) {
      if (target[key] != null) continue;
      if (!await deleteSecure(_storage, key)) complete = false;
    }
    for (final key in kEndpointKeys) {
      if (!changes.containsKey(key)) continue;
      final value = target[key];
      if (value == null) {
        await deleteSecure(_storage, key);
      } else {
        await writeSecure(_storage, key, value);
      }
    }
    if (complete) {
      await _clearCredentialInvalidation(prefs);
    } else {
      if (invalidateOnFailure) await _markCredentialsInvalidated(prefs);
      markCredentialPersistenceFailed();
    }
    return complete;
  }
}
