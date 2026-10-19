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

/// Values written or deleted through [writeSecure]/[deleteSecure] in this
/// process, per store, `null` marking a deletion. A sign-in writes the new
/// credentials, then the app rebuilds its session container and reads them
/// back; after a refused keychain those reads must see this run's writes,
/// never storage. Keyed by the store so each session container reads the
/// same map, while a different store (another isolate, a test) starts clean.
final Expando<Map<String, String?>> _writtenThisRun = Expando(
  'secure credentials written this run',
);

Map<String, String?> _memoryOf(FlutterSecureStorage storage) =>
    _writtenThisRun[storage] ??= {};

/// Whether the keychain refused a read in this process. Once it has, launch
/// reads skip the keychain, so one launch asks the user at most once.
bool get keychainRefusedThisRun => _keychainRefused;

/// Whether a credential write or delete failed in this process. The sign-in
/// path shows one notice when it did: the sign-in works for this run, but it
/// could not be saved for the next launch.
bool get credentialWriteFailedThisRun => _writeFailed;

/// Forgets this run's refusal and write failure. Per-store writes die with
/// the store.
@visibleForTesting
void debugResetKeychainRefusal() {
  _keychainRefused = false;
  _writeFailed = false;
}

/// Matches the next sign-in's notice to that sign-in's writes.
void resetCredentialWriteFailure() => _writeFailed = false;

String _describe(Object error) =>
    error is PlatformException ? error.code : error.runtimeType.toString();

/// Reads [key] on the launch path. A refused keychain read (macOS denied
/// prompt) reads as absent so launch proceeds, and later reads skip the
/// keychain. Callers read one at a time, so a refusal stops the rest before
/// they prompt. A throwing build would be retried by Riverpod and re-prompt.
///
/// Once refused, a value written this run is returned instead of the absent
/// fallback: after the user signs in again, the session container restarted by
/// that sign-in still reads the new credentials, and no read touches the
/// keychain again.
Future<String?> readSecureOrAbsent(
  FlutterSecureStorage storage,
  String key,
) async {
  if (_keychainRefused) return _writtenOrAbsent(storage, key);
  try {
    return await storage.read(key: key);
  } catch (error) {
    _keychainRefused = true;
    logger.w(
      'Keychain refused a read for $key; treating credentials as absent for '
      'this run: ${_describe(error)}',
    );
    // This run's writes are still readable even though the keychain now
    // refuses, so the very key that failed can hold a fresh sign-in.
    return _writtenOrAbsent(storage, key);
  }
}

String? _writtenOrAbsent(FlutterSecureStorage storage, String key) {
  final written = _writtenThisRun[storage];
  return written != null && written.containsKey(key) ? written[key] : null;
}

/// Writes [value] to [storage], remembering it for this run first. A write
/// the keychain refuses is not thrown: the sign-in already succeeded, so it
/// works for this run from memory and the caller only needs to tell the user
/// it was not saved. Returns whether the value reached the platform store.
Future<bool> writeSecure(
  FlutterSecureStorage storage,
  String key,
  String? value,
) async {
  _memoryOf(storage)[key] = value;
  try {
    await storage.write(key: key, value: value);
    return true;
  } catch (error) {
    _writeFailed = true;
    // No point prompting again on every later read of another key.
    _keychainRefused = true;
    logger.w(
      'Keychain refused a write for $key; keeping it in memory for this run: '
      '${_describe(error)}',
    );
    return false;
  }
}

/// Deletes [key], remembering the deletion for this run so the deleted value
/// cannot come back through a later read in the same process. A refused
/// delete is not thrown, for the same reason as [writeSecure].
Future<bool> deleteSecure(FlutterSecureStorage storage, String key) async {
  _memoryOf(storage)[key] = null;
  try {
    await storage.delete(key: key);
    return true;
  } catch (error) {
    _writeFailed = true;
    _keychainRefused = true;
    logger.w(
      'Keychain refused a delete for $key; treating it as deleted for this '
      'run: ${_describe(error)}',
    );
    return false;
  }
}
