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

/// Uses secure platform storage for bearer-equivalent secrets.
/// Android migration keeps a backup; unrecoverable decryption errors reset the store for re-login.
@Riverpod(keepAlive: true)
FlutterSecureStorage secureStorage(Ref ref) => kSecureStorage;

/// Background isolates must use the same storage options to access the same credentials.
const kSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(migrateWithBackup: true),
  // The login keychain works unsigned; the data-protection keychain requires a restricted entitlement.
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);

bool _keychainRefused = false;
bool _writeFailed = false;

/// A refused read suppresses further keychain prompts for this launch.
bool get keychainRefusedThisRun => _keychainRefused;

/// Failed persistence leaves sign-in active in memory but unsaved for the next launch.
bool get credentialWriteFailedThisRun => _writeFailed;

@visibleForTesting
void debugResetKeychainRefusal() {
  _keychainRefused = false;
  _writeFailed = false;
}

void resetCredentialWriteFailure() => _writeFailed = false;

void markCredentialPersistenceFailed() => _writeFailed = true;

String _describe(Object error) =>
    error is PlatformException ? error.code : error.runtimeType.toString();

/// Refused reads return null and suppress later reads for this launch to avoid repeated prompts.
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

/// Returns whether persistence succeeded; refusal leaves the caller's in-memory value active.
Future<bool> writeSecure(
  FlutterSecureStorage storage,
  String key,
  String? value,
) async {
  try {
    await storage.write(key: key, value: value);
    return true;
  } catch (error) {
    _keychainRefused = true;
    logger.w(
      'Keychain refused a write for $key; keeping it in memory for this run: '
      '${_describe(error)}',
    );
    return false;
  }
}

/// Returns false on refusal; in-memory state remains authoritative until persistence is retried.
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
