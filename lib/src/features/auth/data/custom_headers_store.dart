// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../constants/db_keys.dart';
import '../../../global_providers/global_providers.dart';

/// Generic custom HTTP headers sent with every request to the Suwayomi
/// server (GraphQL, images, login, probes, background workers).
///
/// Motivating use-case: a Suwayomi-Server behind a Cloudflare Tunnel guarded
/// by Zero Trust Access, which requires e.g.
/// `CF-Access-Client-Id` + `CF-Access-Client-Secret` on every request.
/// Stored as a JSON string in SharedPreferences under [DBKeys.customHttpHeaders].
///
/// Manual [NotifierProvider] (no codegen) so no `build_runner` step is needed
/// for this file.
class CustomHttpHeadersNotifier extends Notifier<Map<String, String>> {
  static const _key = 'customHttpHeaders';

  @override
  Map<String, String> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return decode(prefs.getString(_key));
  }

  /// Replace the whole map (used by import/reset flows).
  Future<void> setAll(Map<String, String> headers) async {
    state = Map<String, String>.from(headers);
    await ref.read(sharedPreferencesProvider).setString(_key, encode(state));
  }

  /// Insert or update one header. [name] is trimmed; empty names are ignored.
  Future<void> put(String name, String value) async {
    final key = name.trim();
    if (key.isEmpty) return;
    state = {...state, key: value};
    await ref.read(sharedPreferencesProvider).setString(_key, encode(state));
  }

  /// Remove one header by name (exact match).
  Future<void> remove(String name) async {
    if (!state.containsKey(name)) return;
    state = {...state}..remove(name);
    await ref.read(sharedPreferencesProvider).setString(_key, encode(state));
  }

  /// Remove all custom headers.
  Future<void> clear() async {
    state = const {};
    await ref.read(sharedPreferencesProvider).setString(_key, encode(state));
  }

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
    NotifierProvider<CustomHttpHeadersNotifier, Map<String, String>>(
      CustomHttpHeadersNotifier.new,
    );

/// True when at least one custom header is configured.
final customHttpHeadersEnabledProvider = Provider<bool>(
  (ref) => ref.watch(customHttpHeadersProvider).isNotEmpty,
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

/// DBKeys entry backing this store (kept in sync with the enum).
DBKeys get customHttpHeadersDbKey => DBKeys.customHttpHeaders;
