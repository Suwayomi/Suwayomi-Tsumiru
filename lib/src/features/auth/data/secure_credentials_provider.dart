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

/// Values written, deleted or successfully read through this file in this
/// process, per store, `null` marking an absent or deleted value. A sign-in
/// writes the new credentials, then the app rebuilds its session container
/// and reads them back; after a refused keychain those reads must see this
/// run's writes, never storage. Successful reads are cached too, so a later
/// refused write cannot hide a value that was already read (custom proxy
/// headers). Keyed by the store so each session container reads the same map,
/// while a different store (another isolate, a test) starts clean.
Expando<Map<String, String?>> _writtenThisRun = Expando(
  'secure credentials written this run',
);

/// Keys deleted this run. A refused delete leaves the value in storage, so
/// reads must not resurrect it even while the keychain still serves reads.
Expando<Set<String>> _deletedThisRun = Expando(
  'secure credentials deleted this run',
);

Map<String, String?> _memoryOf(FlutterSecureStorage storage) =>
    _writtenThisRun[storage] ??= {};

Set<String> _deletionsOf(FlutterSecureStorage storage) =>
    _deletedThisRun[storage] ??= {};

/// Whether the keychain refused a read in this process. Once it has, launch
/// reads skip the keychain, so one launch asks the user at most once.
bool get keychainRefusedThisRun => _keychainRefused;

/// Whether a credential write failed in this process. The sign-in path shows
/// one notice when it did: the sign-in works for this run, but it could not be
/// saved for the next launch.
bool get credentialWriteFailedThisRun => _writeFailed;

/// Forgets this run's refusal, write failure and remembered values, as a
/// fresh launch would.
@visibleForTesting
void debugResetKeychainRefusal() {
  _keychainRefused = false;
  _writeFailed = false;
  _writtenThisRun = Expando('secure credentials written this run');
  _deletedThisRun = Expando('secure credentials deleted this run');
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
/// A key deleted this run reads as absent without touching the keychain, even
/// if the delete was refused. Once the keychain has refused, values already
/// read or written this run stand in for it, so after the user signs in again
/// the session container restarted by that sign-in still reads the new
/// credentials, and no read touches the keychain again.
Future<String?> readSecureOrAbsent(
  FlutterSecureStorage storage,
  String key,
) async {
  if (_deletionsOf(storage).contains(key)) return null;
  if (_keychainRefused) return _remembered(storage, key);
  try {
    final value = await storage.read(key: key);
    _memoryOf(storage)[key] = value;
    return value;
  } catch (error) {
    _keychainRefused = true;
    logger.w(
      'Keychain refused a read for $key; treating credentials as absent for '
      'this run: ${_describe(error)}',
    );
    // This run's writes are still readable even though the keychain now
    // refuses, so the very key that failed can hold a fresh sign-in.
    return _remembered(storage, key);
  }
}

String? _remembered(FlutterSecureStorage storage, String key) {
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
  _deletionsOf(storage).remove(key);
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
///
/// A refused delete neither marks a write failure nor stops later reads: most
/// deletes here are best-effort cleanups, and the ones that matter for the
/// next launch (sign-out, server switch) record their own durable marker.
Future<bool> deleteSecure(FlutterSecureStorage storage, String key) async {
  _deletionsOf(storage).remove(key);
  _memoryOf(storage)[key] = null;
  try {
    await storage.delete(key: key);
    return true;
  } catch (error) {
    // The value is still in storage; keep it absent for this run.
    _deletionsOf(storage).add(key);
    logger.w(
      'Keychain refused a delete for $key; treating it as deleted for this '
      'run: ${_describe(error)}',
    );
    return false;
  }
}
