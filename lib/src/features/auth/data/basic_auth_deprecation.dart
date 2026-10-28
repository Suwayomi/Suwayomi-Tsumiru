// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../constants/db_keys.dart';
import '../../../global_providers/global_providers.dart';
import '../../../graphql/__generated__/schema.graphql.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../settings/presentation/server/widget/sign_in/graphql/__generated__/sign_in.graphql.dart';

class BasicAuthDeprecationStore {
  BasicAuthDeprecationStore(this._prefs);

  final SharedPreferences _prefs;

  Map<String, int> _readAll() {
    final raw = _prefs.getString(DBKeys.basicAuthDeprecationLastShown.name);
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

  bool isDue(String endpointKey, DateTime now) {
    final last = _readAll()[endpointKey];
    if (last == null) return true;
    final elapsed = now.toUtc().millisecondsSinceEpoch - last;
    return elapsed >= const Duration(days: 7).inMilliseconds;
  }

  Future<void> markShown(String endpointKey, DateTime now) async {
    final all = _readAll();
    all[endpointKey] = now.toUtc().millisecondsSinceEpoch;
    await _prefs.setString(
      DBKeys.basicAuthDeprecationLastShown.name,
      jsonEncode(all),
    );
  }
}

final basicAuthDeprecationStoreProvider = Provider<BasicAuthDeprecationStore>((
  ref,
) {
  return BasicAuthDeprecationStore(ref.watch(sharedPreferencesProvider));
});

Future<Enum$AuthMode?> queryServerAuthMode(GraphQLClient client) async {
  try {
    final settings = await client
        .query$ServerSignInStatus(
          Options$Query$ServerSignInStatus(fetchPolicy: FetchPolicy.noCache),
        )
        .getData((data) => data.settings);
    return settings?.authMode;
  } catch (_) {
    return null;
  }
}
