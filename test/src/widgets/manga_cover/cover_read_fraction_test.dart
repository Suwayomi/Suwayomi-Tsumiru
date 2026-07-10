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
    });

    test('fully read is 1.0', () {
      expect(coverReadFraction(totalChapters: 8, unreadCount: 0), 1.0);
    });

    test('nothing read yet -> null (no bar)', () {
      expect(coverReadFraction(totalChapters: 10, unreadCount: 10), isNull);
    });

    test('no chapters -> null', () {
      expect(coverReadFraction(totalChapters: 0, unreadCount: 0), isNull);
    });

    test('unread greater than total clamps instead of going negative', () {
      expect(coverReadFraction(totalChapters: 5, unreadCount: 9), isNull);
    });
  });
}
