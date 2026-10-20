// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';

void main() {
  group('updatesFilterInput', () {
    test('inverts unread into the server isRead field', () {
      final unread = updatesFilterInput((
        downloaded: null,
        unread: true,
        started: null,
        bookmarked: null,
      ));
      expect(unread.isRead?.equalTo, false);

      final read = updatesFilterInput((
        downloaded: null,
        unread: false,
        started: null,
        bookmarked: null,
      ));
      expect(read.isRead?.equalTo, true);

      // Komikku's updatesView.sq requires read = 0 on BOTH sides of started,
      // so a finished chapter is neither started nor not-started.
      final started = updatesFilterInput((
        downloaded: null,
        unread: null,
        started: true,
        bookmarked: null,
      ));
      expect(started.and, hasLength(2));
      expect(started.and!.first.isRead?.equalTo, false);
      expect(started.and!.last.lastPageRead?.greaterThan, 0);
    });
  });
}
