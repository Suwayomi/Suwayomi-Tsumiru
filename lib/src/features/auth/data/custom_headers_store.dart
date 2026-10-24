// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../global_providers/global_providers.dart';
import 'credential_snapshot.dart';
import 'secure_credentials_provider.dart';

/// Custom headers are bearer-equivalent secrets and must remain in secure storage.
/// Preloaded before the first frame for synchronous request builders.
class CustomHttpHeadersStore extends AsyncNotifier<Map<String, String>> {
  static const secureKey = kCustomHeadersKey;

  @override
  Future<Map<String, String>> build() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final vault = credentialSnapshot(ref.read(secureStorageProvider), prefs);
    await vault.ensureLoaded(prefs);
    return decode(vault[secureKey]);
  }

  Future<void> _persist(Map<String, String> headers) async {
    state = AsyncData(Map<String, String>.from(headers));
    final prefs = ref.read(sharedPreferencesProvider);
    await credentialSnapshot(
      ref.read(secureStorageProvider),
      prefs,
    ).update({secureKey: headers.isEmpty ? null : encode(headers)}, prefs);
  }

  Future<void> setAll(Map<String, String> headers) async =>
      _persist(Map<String, String>.from(headers));

  /// Trims [name] and ignores empty names.
  Future<void> put(String name, String value) async {
    final key = name.trim();
    if (key.isEmpty) return;
    final base = await future;
    await _persist({...base, key: value});
  }

  Future<void> remove(String name) async {
    final base = await future;
    if (!base.containsKey(name)) return;
    await _persist({...base}..remove(name));
  }

  Future<void> clear() => _persist(const {});

  /// Malformed persisted data decodes to an empty map without throwing.
  static Map<String, String> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, String>{};
      for (final entry in decoded.entries) {
        final k = entry.key.toString().trim();
        if (k.isEmpty) continue;
        out[k] = entry.value.toString();
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  static String encode(Map<String, String> headers) => jsonEncode(headers);
}

final customHttpHeadersProvider =
    AsyncNotifierProvider<CustomHttpHeadersStore, Map<String, String>>(
      CustomHttpHeadersStore.new,
    );

/// Accepts RFC 7230 header-name tokens; returns null when valid or an editor error.
String? validateCustomHeaderName(String name, {Map<String, String>? existing}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'empty';
  if (trimmed.contains(':') ||
      trimmed.contains(' ') ||
      trimmed.contains('\t') ||
      trimmed.contains('\n') ||
      trimmed.contains('\r')) {
    return 'invalid';
  }
  if (trimmed.length > 256) return 'too-long';
  return null;
}

/// Merges custom headers without overwriting Authorization or Cookie; returns [headers].
Map<String, String> applyCustomHeaders(
  Map<String, String> headers, [
  Map<String, String>? custom,
]) {
  if (custom == null || custom.isEmpty) return headers;
  for (final entry in custom.entries) {
    final lower = entry.key.toLowerCase();
    if (lower == 'authorization' || lower == 'cookie') continue;
    headers[entry.key] = entry.value;
  }
  return headers;
}
