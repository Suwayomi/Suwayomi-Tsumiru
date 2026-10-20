// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';

NotificationWorkerConfig config({
  Set<int> include = const {},
  Set<int> exclude = const {},
}) => NotificationWorkerConfig(
  serverId: 's',
  endpoint: const NotificationEndpoint(baseUrl: 'http://x'),
  newChaptersEnabled: true,
  includedCategoryIds: include,
  excludedCategoryIds: exclude,
  hideContent: false,
);

void main() {
  group('category scope', () {
    test('filters series by include/exclude, with exclude winning', () {
      final mangaCats = {
        10: {1},
        20: {2},
        30: {1, 2},
      };
      // No include/exclude -> null (all series).
      expect(config().allowedMangaIds(mangaCats), isNull);
      // Include keeps only series in those categories.
      expect(config(include: {1}).allowedMangaIds(mangaCats), {10, 30});
      // Exclude drops series in excluded categories.
      expect(config(exclude: {2}).allowedMangaIds(mangaCats), {10});
      // Exclude wins over include.
      expect(config(include: {1}, exclude: {2}).allowedMangaIds(mangaCats), {
        10,
      });
    });
  });
}
