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

/// Whether the keychain refused a read in this process. Once it has, launch
/// reads skip the keychain, so one launch asks the user at most once.
bool get keychainRefusedThisRun => _keychainRefused;

@visibleForTesting
void debugResetKeychainRefusal() => _keychainRefused = false;

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
      'this run: ${error is PlatformException ? error.code : error.runtimeType}',
    );
    return null;
  }
}
