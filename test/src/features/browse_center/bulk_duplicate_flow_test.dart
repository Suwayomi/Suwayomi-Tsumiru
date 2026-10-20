// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/presentation/source_manga_list/controller/bulk_duplicate_flow.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';

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
  trackRecords: Fragment$MangaDto$trackRecords(nodes: nodes),
);

void main() {
  group('splitSelectionForDuplicates', () {
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
  });
}
