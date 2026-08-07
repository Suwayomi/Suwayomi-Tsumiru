// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/offline/data/offline_chapter_catchup.dart';

typedef _Node = ({int mangaId, int fetchedAt});

void main() {
  test(
    'collects keep-rule manga newer than the watermark, stops at it',
    () async {
      final calls = <int>[];
      Future<List<_Node>?> fetch(int page) async {
        calls.add(page);
        return [
          (mangaId: 1, fetchedAt: 300),
          (mangaId: 2, fetchedAt: 250),
          (mangaId: 3, fetchedAt: 200),
          (mangaId: 1, fetchedAt: 100), // at the watermark — scan ends here
          (mangaId: 4, fetchedAt: 50),
        ];
      }

      final scan = await touchedSinceWatermark(
        fetchPage: fetch,
        keepRuleManga: {1, 3, 4},
        watermark: 100,
      );
      expect(
        scan.touched,
        {1, 3},
        reason:
            'manga 2 has no keep rule, manga 4 is behind the watermark; '
            'manga 1 at the boundary second is re-included',
      );
      expect(scan.newestFetchedAt, 300);
      expect(scan.sawWatermark, isTrue);
      expect(calls, [0], reason: 'the sub-watermark entry ends the scan');
    },
  );

  test('entries sharing the boundary second are not dropped', () async {
    Future<List<_Node>?> fetch(int page) async => [
      (mangaId: 5, fetchedAt: 100),
      (mangaId: 6, fetchedAt: 100),
      (mangaId: 7, fetchedAt: 99),
    ];

    final scan = await touchedSinceWatermark(
      fetchPage: fetch,
      keepRuleManga: {5, 6, 7},
      watermark: 100,
    );
    expect(
      scan.touched,
      {5, 6},
      reason:
          'both boundary-second manga are re-processed, the strictly '
          'older one is not',
    );
    expect(scan.sawWatermark, isTrue);
  });

  test('first run reads a single page instead of the whole feed', () async {
    final calls = <int>[];
    // A full page (50) would normally request the next one.
    Future<List<_Node>?> fetch(int page) async {
      calls.add(page);
      return [for (var i = 0; i < 50; i++) (mangaId: i, fetchedAt: 1000 - i)];
    }

    final scan = await touchedSinceWatermark(
      fetchPage: fetch,
      keepRuleManga: {1, 2},
      watermark: 0,
    );
    expect(calls, [0]);
    expect(scan.newestFetchedAt, 1000);
    expect(
      scan.sawWatermark,
      isFalse,
      reason:
          'a first run reports the tail unknown, so the caller falls '
          'back to a full keep-rule pass',
    );
  });

  test(
    'a full page continues to the next, a short page ends the scan',
    () async {
      final calls = <int>[];
      Future<List<_Node>?> fetch(int page) async {
        calls.add(page);
        if (page == 0) {
          return [
            for (var i = 0; i < 50; i++) (mangaId: 1, fetchedAt: 2000 - i),
          ];
        }
        return [(mangaId: 2, fetchedAt: 1500)];
      }

      final scan = await touchedSinceWatermark(
        fetchPage: fetch,
        keepRuleManga: {1, 2},
        watermark: 10,
      );
      expect(calls, [0, 1]);
      expect(scan.touched, {1, 2});
      expect(scan.newestFetchedAt, 2000);
      expect(scan.sawWatermark, isTrue, reason: 'a short page ends the feed');
    },
  );

  test('feed scan is bounded even when every page is full', () async {
    final calls = <int>[];
    Future<List<_Node>?> fetch(int page) async {
      calls.add(page);
      return [
        for (var i = 0; i < 50; i++)
          (mangaId: page * 50 + i, fetchedAt: 100000 - page * 50 - i),
      ];
    }

    final scan = await touchedSinceWatermark(
      fetchPage: fetch,
      keepRuleManga: {1},
      watermark: 10,
    );
    expect(
      calls,
      hasLength(3),
      reason: 'the page budget caps a stale-watermark scan',
    );
    expect(
      scan.sawWatermark,
      isFalse,
      reason:
          'an exhausted budget must not pass off the unseen tail as '
          'covered — the caller falls back to a full keep-rule pass',
    );
  });
}
