// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../utils/logger/logger.dart';

part 'secure_credentials_provider.g.dart';

/// A platform-backed secure key/value store for credentials.
///
/// On Android this is Keystore-backed AES-GCM (v10 migrates old
/// EncryptedSharedPreferences data on first access; the backup keeps a failed
/// migration from destroying stored logins); on iOS the Keychain; on
/// desktop/web best-available platform stores. Always preferred over
/// SharedPreferences for anything bearer-equivalent (passwords, JWTs,
/// session cookies).
///
/// v10's resetOnError default is accepted deliberately: an unrecoverable
/// keystore/decrypt error wipes the store (clean re-login) instead of
/// crashing every read.
@Riverpod(keepAlive: true)
FlutterSecureStorage secureStorage(Ref ref) => kSecureStorage;

/// The store [secureStorage] provides, for the background isolates, which have
/// no Riverpod. They must open it with the very same options to see the same
/// data.
const kSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(migrateWithBackup: true),
  // The data-protection keychain needs a restricted entitlement, and macOS
  // refuses to launch an ad-hoc-signed build that carries one. The login
  // keychain works unsigned.
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);

bool _keychainRefused = false;
bool _writeFailed = false;

/// Whether the keychain refused a read in this process. Once it has, launch
/// reads skip the keychain, so one launch asks the user at most once.
bool get keychainRefusedThisRun => _keychainRefused;

/// Whether a credential state failed to reach secure storage in this process.
/// The sign-in path shows one notice when it did: the sign-in works for this
/// run, but it could not be saved for the next launch.
bool get credentialWriteFailedThisRun => _writeFailed;

/// Forgets this run's refusal and write failure, as a fresh launch would.
@visibleForTesting
void debugResetKeychainRefusal() {
  _keychainRefused = false;
  _writeFailed = false;
}

/// Matches the next sign-in's notice to that sign-in's writes.
void resetCredentialWriteFailure() => _writeFailed = false;

/// Records that the in-memory credentials could not be fully written to the
/// platform store.
void markCredentialPersistenceFailed() => _writeFailed = true;

String _describe(Object error) =>
    error is PlatformException ? error.code : error.runtimeType.toString();

/// Reads [key] on the launch path. A refused keychain read (macOS denied
/// prompt) reads as absent so launch proceeds, and later reads skip the
/// keychain. Callers read one at a time, so a refusal stops the rest before
/// they prompt. A throwing build would be retried by Riverpod and re-prompt.
Future<String?> readSecureOrAbsent(
  FlutterSecureStorage storage,
  String key,
) async {
  if (_keychainRefused) return null;
  try {
    return await storage.read(key: key);
  } catch (error) {
    _keychainRefused = true;
    logger.w(
      'Keychain refused a read for $key; treating credentials as absent for '
      'this run: ${_describe(error)}',
    );
    return null;
  }
}

/// Writes [value] to [storage]. A write the keychain refuses is not thrown:
/// the caller keeps the value in memory for this run and only needs to tell
/// the user it was not saved. Returns whether the value reached the platform
/// store.
Future<bool> writeSecure(
  FlutterSecureStorage storage,
  String key,
  String? value,
) async {
  try {
    await storage.write(key: key, value: value);
    return true;
  } catch (error) {
    // No point prompting again on every later read of another key.
    _keychainRefused = true;
    logger.w(
      'Keychain refused a write for $key; keeping it in memory for this run: '
      '${_describe(error)}',
    );
    return false;
  }
}

/// Deletes [key]. A refused delete is not thrown, for the same reason as
/// [writeSecure]: the caller's in-memory state is the source of truth, and the
/// next mutation retries the complete state anyway.
Future<bool> deleteSecure(FlutterSecureStorage storage, String key) async {
  try {
    await storage.delete(key: key);
    return true;
  } catch (error) {
    logger.w(
      'Keychain refused a delete for $key; retrying on the next credential '
      'mutation: ${_describe(error)}',
    );
    return false;
  }
}
