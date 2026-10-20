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
}
