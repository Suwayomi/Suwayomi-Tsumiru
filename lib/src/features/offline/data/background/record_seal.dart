// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import '../../../../utils/crash/diagnostics.dart';
import '../../../auth/data/secure_credentials_provider.dart';

/// Seals backup-readable worker credentials with AES-256-GCM under a secure-storage key.
/// Each isolate must load the key before reading or writing records.
abstract final class RecordSeal {
  static const storageKey = 'auth.background.sealKey';
  static const _prefix = 'v1';

  static Uint8List? _key;

  static bool get ready => _key != null;

  /// Only the app may create the shared key; workers load it. Returns whether it is available.
  static Future<bool> load(
    FlutterSecureStorage storage, {
    bool create = false,
  }) async {
    try {
      final stored = await readSecureOrAbsent(storage, storageKey);
      if (stored == null && keychainRefusedThisRun) {
        _log('key-unreadable cause=refused');
        return false;
      }
      final bytes = stored == null ? null : _decodeKey(stored);
      if (bytes != null && bytes.length == 32) {
        _key = bytes;
        return true;
      }
      if (!create) {
        _log('key-missing');
        return false;
      }
      final fresh = _randomBytes(32);
      // Do not seal with a key that failed to persist; later runs could never decrypt it.
      if (!await writeSecure(storage, storageKey, base64Encode(fresh))) {
        return false;
      }
      _key = fresh;
      _log('key-created');
      return true;
    } catch (e) {
      _log('key-unreadable cause=${e.runtimeType}');
      return false;
    }
  }

  static Uint8List? _decodeKey(String stored) {
    try {
      return base64Decode(stored);
    } on FormatException {
      return null;
    }
  }

  @visibleForTesting
  static set debugKey(Uint8List? key) => _key = key;

  /// Throws without a loaded key; never falls back to plaintext.
  static String seal(Map<String, Object?> secrets) {
    final key = _key;
    if (key == null) {
      throw StateError('Background credentials key not loaded');
    }
    final nonce = _randomBytes(12);
    final sealed = _cipher(
      key,
      nonce,
      encrypt: true,
    ).process(Uint8List.fromList(utf8.encode(jsonEncode(secrets))));
    return '$_prefix.${base64Encode(nonce)}.${base64Encode(sealed)}';
  }

  /// Null for unavailable keys or tampering; unreadable records authenticate as nobody.
  static Map<String, Object?>? open(String sealed) {
    final key = _key;
    if (key == null) {
      _log('open-failed reason=no-key');
      return null;
    }
    try {
      final parts = sealed.split('.');
      if (parts.length != 3 || parts[0] != _prefix) {
        throw const FormatException('unknown format');
      }
      final plain = _cipher(
        key,
        base64Decode(parts[1]),
        encrypt: false,
      ).process(base64Decode(parts[2]));
      return (jsonDecode(utf8.decode(plain)) as Map).cast<String, Object?>();
    } catch (e) {
      _log('open-failed reason=${e.runtimeType}');
      return null;
    }
  }

  static GCMBlockCipher _cipher(
    Uint8List key,
    Uint8List nonce, {
    required bool encrypt,
  }) => GCMBlockCipher(
    AESEngine(),
  )..init(encrypt, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static void _log(String event) => recordDiagnostic(
    '[${DateTime.now().toIso8601String()}] record-seal: $event\n',
  );
}
