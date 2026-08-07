// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/manga_book/data/updates/updates_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/updates/updates_filter.dart';

void main() {
  group('updatesFilterInput', () {
    test('always scopes to the library', () {
      final input = updatesFilterInput(kNoUpdatesFilter);
      expect(input.inLibrary?.equalTo, true);
    });

    test('leaves every field unset when nothing is filtered', () {
      final input = updatesFilterInput(kNoUpdatesFilter);
      expect(input.isDownloaded, isNull);
      expect(input.isRead, isNull);
      expect(input.isBookmarked, isNull);
      expect(input.and, isNull);
    });

    test('maps downloaded and bookmarked straight through', () {
      final included = updatesFilterInput((
        downloaded: true,
        unread: null,
        started: null,
        bookmarked: true,
      ));
      expect(included.isDownloaded?.equalTo, true);
      expect(included.isBookmarked?.equalTo, true);

      final excluded = updatesFilterInput((
        downloaded: false,
        unread: null,
        started: null,
        bookmarked: false,
      ));
      expect(excluded.isDownloaded?.equalTo, false);
      expect(excluded.isBookmarked?.equalTo, false);
    });

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
    });

    // Komikku's updatesView.sq requires read = 0 on BOTH sides of started, so a
    // finished chapter is neither started nor not-started.
    test('started keeps only unread chapters with progress', () {
      final input = updatesFilterInput((
        downloaded: null,
        unread: null,
        started: true,
        bookmarked: null,
      ));
      expect(input.and, hasLength(2));
      expect(input.and!.first.isRead?.equalTo, false);
      expect(input.and!.last.lastPageRead?.greaterThan, 0);
    });

    test('not-started keeps only unread chapters without progress', () {
      final input = updatesFilterInput((
        downloaded: null,
        unread: null,
        started: false,
        bookmarked: null,
      ));
      expect(input.and, hasLength(2));
      expect(input.and!.first.isRead?.equalTo, false);
      expect(input.and!.last.lastPageRead?.equalTo, 0);
    });
  });
}
