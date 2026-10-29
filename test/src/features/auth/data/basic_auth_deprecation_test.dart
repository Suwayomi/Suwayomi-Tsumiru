// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/basic_auth_deprecation.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

void main() {
  test(
    'reminders repeat after seven days and survive restart per server',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      ProviderContainer containerFor() => ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      final container = containerFor();
      addTearDown(container.dispose);
      final now = DateTime.utc(2026, 10, 28);
      const server = 'https://example.org:4567';

      final notices = container.read(
        basicAuthDeprecationLastShownProvider.notifier,
      );
      expect(notices.isDue(server, now), isTrue);
      notices.markShown(server, now);

      final restarted = containerFor();
      addTearDown(restarted.dispose);
      final restored = restarted.read(
        basicAuthDeprecationLastShownProvider.notifier,
      );
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
}
