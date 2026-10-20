// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';

void main() {
  group('coverReadFraction', () {
    test('reports the read fraction', () {
      expect(coverReadFraction(totalChapters: 10, unreadCount: 3), 0.7);
      expect(coverReadFraction(totalChapters: 8, unreadCount: 0), 1.0);

      // Nothing read, no chapters or more unread than total -> null.
      expect(coverReadFraction(totalChapters: 10, unreadCount: 10), isNull);
      expect(coverReadFraction(totalChapters: 0, unreadCount: 0), isNull);
      // Clamps instead of going negative.
      expect(coverReadFraction(totalChapters: 5, unreadCount: 9), isNull);
    });
  });
}
