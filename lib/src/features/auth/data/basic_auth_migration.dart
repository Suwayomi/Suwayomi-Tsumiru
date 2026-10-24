// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credential_snapshot.dart';
import 'secure_credentials_provider.dart';

const kBasicCredentialsSecureKey = kBasicCredentialsKey;

const kLegacyBasicCredentialsKey = 'basicCredentials';

/// Clears the legacy copy so a deferred migration cannot restore a signed-out account.
Future<void> clearLegacyBasicCredentials(SharedPreferences prefs) =>
    prefs.remove(kLegacyBasicCredentialsKey);

/// Moves legacy Basic credentials to secure storage, preferring an existing secure value.
/// Deletes the plaintext legacy copy only after secure storage succeeds.
Future<void> migrateBasicAuthCredentials({
  required SharedPreferences prefs,
  required FlutterSecureStorage secure,
}) async {
  final legacy = prefs.getString(kLegacyBasicCredentialsKey);
  if (legacy == null) return;

  // Capture invalidation before cleanup so the legacy copy cannot undo a sign-out.
  final invalidated = credentialsInvalidated(prefs);
  final vault = credentialSnapshot(secure, prefs);
  await vault.ensureLoaded(prefs);
  // A refused keychain keeps the legacy copy for the next launch.
  if (keychainRefusedThisRun) return;
  if (invalidated) {
    await clearLegacyBasicCredentials(prefs);
    return;
  }
  if (vault[kBasicCredentialsSecureKey] == null) {
    // Preserve the durable legacy copy on failure without setting the invalidation marker.
    final moved = await vault.update(
      {kBasicCredentialsSecureKey: legacy},
      prefs,
      invalidateOnFailure: false,
    );
    if (!moved) return;
  }
  await clearLegacyBasicCredentials(prefs);
}
