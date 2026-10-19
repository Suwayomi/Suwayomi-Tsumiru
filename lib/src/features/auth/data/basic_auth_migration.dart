// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credential_snapshot.dart';
import 'secure_credentials_provider.dart';

/// Secure-storage key under which basic-auth credentials now live.
const kBasicCredentialsSecureKey = kBasicCredentialsKey;

/// Legacy SharedPreferences key (DBKeys.basicCredentials.name).
const kLegacyBasicCredentialsKey = 'basicCredentials';

/// Removes the legacy plaintext Basic credential, if one is left. Every
/// explicit credential clear calls this: a migration deferred while the
/// keychain was refused would otherwise re-import the cleared sign-in on a
/// later launch.
Future<void> clearLegacyBasicCredentials(SharedPreferences prefs) =>
    prefs.remove(kLegacyBasicCredentialsKey);

/// One-time, idempotent migration of basic-auth credentials from the
/// plaintext-equivalent SharedPreferences store to platform secure storage.
///
/// If a credential exists in the legacy location:
///   - And nothing is in secure storage yet → move it.
///   - And something is already in secure storage → keep the secure-store
///     value (user may have re-entered credentials more recently); just
///     clear the legacy copy.
///
/// Either way, the legacy SharedPreferences entry is deleted at the end so
/// the plaintext copy doesn't linger.
Future<void> migrateBasicAuthCredentials({
  required SharedPreferences prefs,
  required FlutterSecureStorage secure,
}) async {
  final legacy = prefs.getString(kLegacyBasicCredentialsKey);
  if (legacy == null) return;

  // Captured before the load: a successful cleanup clears the marker, but the
  // storage it cleared held a sign-out that the legacy copy must not undo.
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
    // Keep the legacy copy if the move failed, so the next launch retries.
    if (!await vault.update({kBasicCredentialsSecureKey: legacy}, prefs)) {
      return;
    }
  }
  await clearLegacyBasicCredentials(prefs);
}
