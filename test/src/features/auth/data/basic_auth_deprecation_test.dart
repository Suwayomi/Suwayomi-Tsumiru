// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/basic_auth_deprecation.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

void main() {
  test(
    'reminders repeat after seven days and survive restart per server',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = BasicAuthDeprecationStore(prefs);
      final now = DateTime.utc(2026, 10, 28);
      const server = 'https://example.org:4567';

      expect(store.isDue(server, now), isTrue);
      await store.markShown(server, now);
      final restored = BasicAuthDeprecationStore(prefs);
      expect(restored.isDue(server, now), isFalse);
      expect(restored.isDue('https://example.org:4568', now), isTrue);
      expect(
        restored.isDue(
          server,
          now
              .add(const Duration(days: 7))
              .subtract(const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
      expect(restored.isDue(server, now.add(const Duration(days: 7))), isTrue);
    },
  );

  test(
    'auth mode comes from the live server and failures return no mode',
    () async {
      String? mode = 'BASIC_AUTH';
      var requests = 0;
      final client = GraphQLClient(
        cache: GraphQLCache(),
        link: Link.function((request, [forward]) async* {
          requests++;
          if (mode == null) throw StateError('offline');
          yield Response(
            data: {
              '__typename': 'Query',
              'settings': {
                '__typename': 'SettingsType',
                'authMode': mode,
                'jwtAudience': 'suwayomi',
              },
            },
            response: {},
          );
        }),
      );
      expect(await queryServerAuthMode(client), Enum$AuthMode.BASIC_AUTH);
      mode = 'UI_LOGIN';
      expect(await queryServerAuthMode(client), Enum$AuthMode.UI_LOGIN);
      mode = 'NONE';
      expect(await queryServerAuthMode(client), Enum$AuthMode.NONE);
      mode = null;
      expect(await queryServerAuthMode(client), isNull);
      expect(requests, 4);
    },
  );
}
