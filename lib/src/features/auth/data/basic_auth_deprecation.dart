// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'basic_auth_deprecation.g.dart';

@riverpod
class BasicAuthDeprecationLastShown extends _$BasicAuthDeprecationLastShown
    with SharedPreferenceClientMixin<String> {
  @override
  String? build() => initialize(DBKeys.basicAuthDeprecationLastShown);

  bool isDue(String endpointKey, DateTime now) {
    final last = _lastShownByEndpoint(state)[endpointKey];
    if (last == null) return true;
    return now.toUtc().millisecondsSinceEpoch - last >=
        const Duration(days: 7).inMilliseconds;
  }

  void markShown(String endpointKey, DateTime now) {
    final all = _lastShownByEndpoint(state);
    all[endpointKey] = now.toUtc().millisecondsSinceEpoch;
    update(jsonEncode(all));
  }
}

Map<String, int> _lastShownByEndpoint(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final entry in decoded.entries)
        if (entry.value is int) entry.key.toString(): entry.value as int,
    };
  } catch (_) {
    return {};
  }
}
