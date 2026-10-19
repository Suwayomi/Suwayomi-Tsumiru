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

/// Secure-storage key for the password older versions wrote although nothing
/// ever read it back. Still deleted so an upgrade removes it.
const kLegacyPasswordSecureKey = 'auth.password';
const kSimpleLoginCookieSecureKey = 'auth.simple.cookie';
const kUiAccessTokenSecureKey = 'auth.ui.accessToken';
const kUiRefreshTokenSecureKey = 'auth.ui.refreshToken';
const kUiAccountBindingSecureKey = 'auth.ui.accountBinding';
const kBasicCredentialsKey = 'auth.basic.credentials';
const kCustomHeadersKey = 'custom.headers';

/// Every account credential the app keeps in secure storage. A persist writes
/// the ones with a value and deletes the rest, so storage either matches the
/// snapshot exactly or the marker says it cannot be trusted.
const kCredentialKeys = <String>[
  kLegacyPasswordSecureKey,
  kSimpleLoginCookieSecureKey,
  kUiAccessTokenSecureKey,
  kUiRefreshTokenSecureKey,
  kUiAccountBindingSecureKey,
  kBasicCredentialsKey,
];

/// Endpoint configuration stored beside the credentials but not part of the
/// account: an account invalidation must not delete these. Each is written
/// only when its own update changes it; a refused write or delete leaves the
/// in-memory value for this run and the stored value for the next launch.
const kEndpointKeys = <String>[kCustomHeadersKey];

/// Whether a credential write or delete was refused, so what is on disk may
/// not match what the app was last signed in with.
bool credentialsInvalidated(SharedPreferences prefs) =>
    prefs.getBool(DBKeys.authCredentialsInvalidated.name) ?? false;

Future<void> _markCredentialsInvalidated(SharedPreferences prefs) =>
    prefs.setBool(DBKeys.authCredentialsInvalidated.name, true);

Future<void> _clearCredentialInvalidation(SharedPreferences prefs) =>
    prefs.setBool(DBKeys.authCredentialsInvalidated.name, false);

/// The snapshot and the preferences instance it was loaded under.
class _SnapshotSlot {
  _SnapshotSlot(this.prefs, this.snapshot);

  final SharedPreferences prefs;
  final CredentialSnapshot snapshot;
}

final Expando<_SnapshotSlot> _snapshots = Expando('credential snapshot');

/// The live credential snapshot for [storage].
///
/// Keyed by the store, which outlives every Riverpod container: the app uses
/// the `kSecureStorage` constant, so a session-container restart reads the
/// same snapshot. A keepAlive provider could not do this, because
/// `AccountSessionHost` disposes the whole previous container.
///
/// The preferences instance identifies the launch. The app loads one per
/// process and hands it to every session container; a test that installs new
/// mock preferences starts a new run, so it gets an empty snapshot instead of
/// the previous test's values.
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

/// The source of truth for credentials during a run.
///
/// Loaded once from secure storage at launch, then never re-read: every
/// credential mutation changes these values first and persists the complete
/// set behind them. That keeps a refused keychain from signing the user out
/// mid-run and from restoring a previous account on the next launch.
class CredentialSnapshot {
  CredentialSnapshot._(this._storage);

  final FlutterSecureStorage _storage;
  final Map<String, String?> _values = {};
  Future<void>? _loading;
  Future<void> _persistTail = Future<void>.value();

  String? operator [](String key) => _values[key];

  /// Loads the credential set from secure storage once per run.
  ///
  /// With the invalidation marker set, storage may hold a sign-out or a
  /// previous server's sign-in that a refused delete left behind: start empty
  /// and retry the cleanup, clearing the marker only when every delete lands.
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
      // Older versions stored the sign-in password here although nothing ever
      // read it back. Best effort: it never affects the marker or a read.
      unawaited(deleteSecure(_storage, kLegacyPasswordSecureKey));
    }
    // Endpoint configuration was never invalidated, so it loads either way.
    for (final key in [...kCredentialKeys, ...kEndpointKeys]) {
      if (key == kLegacyPasswordSecureKey) continue;
      if (invalidated && kCredentialKeys.contains(key)) continue;
      _values[key] = await readSecureOrAbsent(_storage, key);
    }
  }

  /// Applies [changes] to the snapshot, then writes the whole account set to
  /// secure storage: the keys with a value are written, every other credential
  /// key is deleted. A failure in any operation sets the invalidation marker,
  /// so the next launch starts signed out rather than trusting a partial write.
  /// Endpoint keys in [changes] are written or deleted on their own and never
  /// affect the marker.
  ///
  /// Returns whether the complete account state reached the platform store.
  Future<bool> update(Map<String, String?> changes, SharedPreferences prefs) {
    _values.addAll(changes);
    final target = Map<String, String?>.from(_values);
    final result = _persistTail.then((_) => _persist(target, changes, prefs));
    _persistTail = result.then((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<bool> _persist(
    Map<String, String?> target,
    Map<String, String?> changes,
    SharedPreferences prefs,
  ) async {
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
      await _markCredentialsInvalidated(prefs);
      markCredentialPersistenceFailed();
    }
    return complete;
  }
}
