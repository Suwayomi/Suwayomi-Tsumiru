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

/// Encrypts the secret fields of [BackgroundTokenRecord]s.
///
/// The background workers keep their copy of the credentials in plain
/// SharedPreferences (the notification worker's record) and in the
/// foreground-task plugin's storage, which is SharedPreferences too. Both are
/// readable from a device backup, unlike secure storage. The records keep
/// living there, so the workers' locking and cross-isolate reads stay as they
/// are, but their secrets are sealed with AES-256-GCM under a key held in
/// secure storage, which a backup can't decrypt.
///
/// Every isolate that reads or writes records loads the key first: the app at
/// launch ([load] with `create: true`), and each worker at its entry point.
abstract final class RecordSeal {
  static const storageKey = 'auth.background.sealKey';
  static const _prefix = 'v1';

  static Uint8List? _key;

  /// Whether this isolate has a key to seal and open records with.
  static bool get ready => _key != null;

  /// Loads the key from [storage]. Only the app creates one ([create]): a
  /// worker that found none would seal records nobody else could open.
  /// Returns whether a key is loaded.
  static Future<bool> load(
    FlutterSecureStorage storage, {
    bool create = false,
  }) async {
    try {
      final stored = await storage.read(key: storageKey);
      final bytes = stored == null ? null : base64Decode(stored);
      if (bytes != null && bytes.length == 32) {
        _key = bytes;
        return true;
      }
      if (!create) {
        _log('key-missing');
        return false;
      }
      final fresh = _randomBytes(32);
      await storage.write(key: storageKey, value: base64Encode(fresh));
      _key = fresh;
      _log('key-created');
      return true;
    } catch (e) {
      _log('key-unreadable cause=${e.runtimeType}');
      return false;
    }
  }

  @visibleForTesting
  static set debugKey(Uint8List? key) => _key = key;

  /// [secrets] as an opaque string. Throws when no key is loaded: writing
  /// them in clear is exactly what this exists to prevent.
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

  /// The secrets [sealed] holds, or null when they can't be read: no key in
  /// this isolate, a key replaced since (secure storage wiped), or tampering.
  /// A record whose secrets can't be read authenticates as nobody.
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
