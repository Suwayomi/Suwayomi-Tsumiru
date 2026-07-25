// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/controller/bulk_duplicate_flow.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/duplicate_manga_dialog.dart';

import '../manga_book/reader/reader_test_fixtures.dart';

Fragment$MangaDto$trackRecords$nodes _node({
  int trackerId = 1,
  String remoteId = '42',
}) => Fragment$MangaDto$trackRecords$nodes(
  id: 1,
  trackerId: trackerId,
  remoteId: remoteId,
  status: 1,
  score: 0,
  title: 'bound',
);

MangaDto _m(
  int id,
  String title, {
  List<Fragment$MangaDto$trackRecords$nodes> nodes = const [],
}) => testManga().copyWith.call(
  id: id,
  title: title,
  trackRecords: Fragment$MangaDto$trackRecords(
    totalCount: nodes.length,
    nodes: nodes,
  ),
);

void main() {
  group('splitSelectionForDuplicates', () {
    test('null library ⇒ everything clean, nothing flagged (fail open)', () {
      final split = splitSelectionForDuplicates(
        selection: [_m(1, 'Alpha'), _m(2, 'Beta')],
        library: null,
      );
      expect(split.cleanIds, [1, 2]);
      expect(split.flagged, isEmpty);
      expect(split.hitIdsByManga, isEmpty);
      expect(split.certainIdsByManga, isEmpty);
    });

    test('a library title hit is flagged with the library id', () {
      final split = splitSelectionForDuplicates(
        selection: [_m(1, 'Solo Leveling!!')],
        library: [_m(10, 'Solo Leveling')],
      );
      expect(split.cleanIds, isEmpty);
      expect(split.flagged.map((m) => m.id), [1]);
      expect(split.hitIdsByManga[1], contains(10));
      // Title-only, so no certain (tracker) match.
      expect(split.certainIdsByManga[1], isEmpty);
    });

    test('intra-selection pair: the second is flagged with the FIRST id', () {
      final split = splitSelectionForDuplicates(
        selection: [_m(1, 'Berserk'), _m(2, 'BERSERK!!')],
        library: const [],
      );
      // The first was ruled clean and becomes a comparator for the second.
      expect(split.cleanIds, [1]);
      expect(split.flagged.map((m) => m.id), [2]);
      expect(split.hitIdsByManga[2], {1});
    });

    test('a shared tracker binding flags as a certain match', () {
      final split = splitSelectionForDuplicates(
        selection: [
          _m(1, 'A totally different title', nodes: [_node(remoteId: '42')]),
        ],
        library: [
          _m(10, 'Unrelated name', nodes: [_node(remoteId: '42')]),
        ],
      );
      expect(split.flagged.map((m) => m.id), [1]);
      expect(split.hitIdsByManga[1], contains(10));
      expect(split.certainIdsByManga[1], contains(10));
    });

    test('a clean member never enters the flagged/hit maps', () {
      final split = splitSelectionForDuplicates(
        selection: [_m(1, 'Unique One'), _m(2, 'Unique Two')],
        library: [_m(10, 'Something Else')],
      );
      expect(split.cleanIds, [1, 2]);
      expect(split.flagged, isEmpty);
    });
  });

  group('classifyDuplicateResult (enum exhaustiveness)', () {
    test('every dialog result maps to a bulk action', () {
      expect(
        classifyDuplicateResult(DuplicateDialogResult.addAnyway),
        BulkDupAction.addThis,
      );
      expect(
        classifyDuplicateResult(DuplicateDialogResult.allowAll),
        BulkDupAction.addRest,
      );
      expect(
        classifyDuplicateResult(DuplicateDialogResult.skipIt),
        BulkDupAction.skipThis,
      );
      expect(
        classifyDuplicateResult(DuplicateDialogResult.skipAll),
        BulkDupAction.skipRest,
      );
      expect(
        classifyDuplicateResult(DuplicateDialogResult.migrated),
        BulkDupAction.handled,
      );
      expect(
        classifyDuplicateResult(DuplicateDialogResult.openedEntry),
        BulkDupAction.openStop,
      );
      expect(
        classifyDuplicateResult(DuplicateDialogResult.cancel),
        BulkDupAction.cancelStop,
      );
    });

    test('a null result (barrier dismiss) cancels the queue', () {
      expect(classifyDuplicateResult(null), BulkDupAction.cancelStop);
    });
  });
}
