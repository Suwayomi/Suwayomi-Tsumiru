// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/notifications/data/background/notification_background_client.dart';
import 'package:tsumiru/src/features/notifications/data/notification_state_store.dart';
import 'package:tsumiru/src/features/notifications/domain/new_chapter_detection.dart';

NotificationWorkerConfig config({
  Set<int> include = const {},
  Set<int> exclude = const {},
}) =>
    NotificationWorkerConfig(
      serverId: 's',
      endpoint: const NotificationEndpoint(baseUrl: 'http://x'),
      newChaptersEnabled: true,
      includedCategoryIds: include,
      excludedCategoryIds: exclude,
      hideContent: false,
    );

void main() {
  group('category scope', () {
    final mangaCats = {10: {1}, 20: {2}, 30: {1, 2}};

    test('no include/exclude -> null (all series)', () {
      expect(config().allowedMangaIds(mangaCats), isNull);
    });

    test('include list keeps only series in those categories', () {
      expect(config(include: {1}).allowedMangaIds(mangaCats), {10, 30});
    });

    test('exclude drops series in excluded categories', () {
      expect(config(exclude: {2}).allowedMangaIds(mangaCats), {10});
    });

    test('exclude wins over include', () {
      expect(config(include: {1}, exclude: {2}).allowedMangaIds(mangaCats), {10});
    });
  });

  test('outbox round-trips through json (crash recovery)', () {
    final outbox = NotificationOutbox(
      pending: [
        const PendingSeriesNotification(
          mangaId: 7,
          mangaTitle: 'M7',
          thumbnailUrl: '/t.jpg',
          chapterIds: [1, 2],
          chapterNumbers: [1, 2],
          firstChapterId: 1,
          totalCount: 2,
        ),
      ],
      nextWatermark: const NewChapterWatermark(fetchedAt: 99, recent: {2: 99}),
    );
    final back = NotificationOutbox.fromJson(outbox.toJson());
    expect(back.pending.single.mangaTitle, 'M7');
    expect(back.pending.single.chapterIds, [1, 2]);
    expect(back.nextWatermark.fetchedAt, 99);
    expect(back.nextWatermark.recent, {2: 99});
  });
}
