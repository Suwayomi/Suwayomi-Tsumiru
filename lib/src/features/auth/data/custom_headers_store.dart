// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'secure_credentials_provider.dart';

/// Generic custom HTTP headers sent with every request to the Suwayomi
/// server (GraphQL, images, login, probes, background workers).
///
/// Motivating use-case: a Suwayomi-Server behind a Cloudflare Tunnel guarded
/// by Zero Trust Access, which requires e.g.
/// `CF-Access-Client-Id` + `CF-Access-Client-Secret` on every request.
///
/// Header values are bearer-equivalent secrets, so the map lives in
/// `flutter_secure_storage` (matching where the app keeps its own tokens),
/// not SharedPreferences.
///
/// Manual [AsyncNotifierProvider] (no codegen) so no `build_runner` step is
/// needed for this file. `main()` preloads the provider before the first
/// frame, so request-building call sites can read the synchronously-cached
/// [AsyncValue.value] (falling back to empty before the load completes).
class CustomHttpHeadersStore extends AsyncNotifier<Map<String, String>> {
  /// Secure-storage key holding the JSON-encoded header map.
  static const secureKey = 'custom.headers';

  @override
  Future<Map<String, String>> build() async {
    try {
      final raw = await ref.read(secureStorageProvider).read(key: secureKey);
      return decode(raw);
    } catch (_) {
      return const {};
    }
  }

  Future<void> _persist(Map<String, String> headers) async {
    state = AsyncData(Map<String, String>.from(headers));
    final storage = ref.read(secureStorageProvider);
    if (headers.isEmpty) {
      await storage.delete(key: secureKey);
    } else {
      await storage.write(key: secureKey, value: encode(headers));
    }
  }

  /// Replace the whole map (used by import/reset flows).
  Future<void> setAll(Map<String, String> headers) async =>
      _persist(Map<String, String>.from(headers));

  /// Insert or update one header. [name] is trimmed; empty names are ignored.
  Future<void> put(String name, String value) async {
    final key = name.trim();
    if (key.isEmpty) return;
    final base = await future;
    await _persist({...base, key: value});
  }

  /// Remove one header by name (exact match).
  Future<void> remove(String name) async {
    final base = await future;
    if (!base.containsKey(name)) return;
    await _persist({...base}..remove(name));
  }

  /// Remove all custom headers.
  Future<void> clear() => _persist(const {});

  /// Decode the persisted JSON string into a header map. Never throws:
  /// malformed input reads as empty.
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

  /// Encode a header map for persistence.
  static String encode(Map<String, String> headers) => jsonEncode(headers);
}

final customHttpHeadersProvider =
    AsyncNotifierProvider<CustomHttpHeadersStore, Map<String, String>>(
  CustomHttpHeadersStore.new,
);

/// Validate a header name for the editor. Returns an error string or null
/// when valid. Header names are RFC 7230 tokens: no spaces, colons, or
/// control characters.
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

/// Merge [custom] into [headers]. Custom headers never overwrite the app's
/// own auth headers (`authorization`, `cookie`) — a mis-typed custom header
/// must not silently break login. Returns [headers] for chaining.
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
