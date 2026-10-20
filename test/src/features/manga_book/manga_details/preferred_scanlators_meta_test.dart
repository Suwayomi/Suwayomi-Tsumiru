// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

class _RecordingRepo extends MangaBookRepository {
  _RecordingRepo({this.failWrites = false}) : super(_dummyClient());
  final bool failWrites;
  final List<(int, String, dynamic)> patched = [];
  @override
  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async {
    if (failWrites) throw Exception('server unreachable');
    patched.add((mangaId, key, value));
  }
}

/// A manga carrying the given raw meta entries.
class _MetaSeededManga extends MangaWithId {
  _MetaSeededManga(this.metaEntries);
  final List<Fragment$MangaDto$meta> metaEntries;
  @override
  Future<MangaDto?> build({required int mangaId}) async => Fragment$MangaDto(
    id: mangaId,
    title: 'M',
    bookmarkCount: 0,
    chapters: Fragment$MangaDto$chapters(totalCount: 0),
    downloadCount: 0,
    genre: const [],
    inLibrary: true,
    inLibraryAt: '0',
    initialized: true,
    meta: metaEntries,
    sourceId: '1',
    status: Enum$MangaStatus.ONGOING,
    categories: Fragment$MangaDto$categories(nodes: const []),
    trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
    unreadCount: 0,
    updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
    url: '/manga/$mangaId',
  );
}

void main() {
  Future<ProviderContainer> seeded(
    _RecordingRepo repo,
    List<Fragment$MangaDto$meta> meta,
  ) async {
    final c = ProviderContainer(
      overrides: [
        mangaBookRepositoryProvider.overrideWithValue(repo),
        mangaWithIdProvider(
          mangaId: 1,
        ).overrideWith(() => _MetaSeededManga(meta)),
      ],
    );
    addTearDown(c.dispose);
    // Resolve the async manga first so the (synchronous) preference provider
    // reads the seeded meta on its first build.
    await c.read(mangaWithIdProvider(mangaId: 1).future);
    return c;
  }

  group('effective preferred scanlators', () {
    test('modern preferences override legacy preference', () {
      expect(
        MangaMeta.fromJson({
          'flutter_preferredScanlators': '["A","B"]',
          'flutter_scanlator': 'Legacy',
        }).effectivePreferredScanlators,
        ['A', 'B'],
      );
    });
  });

  group('setPreference', () {
    test(
      'a failed write reports failure and publishes no local success',
      () async {
        final repo = _RecordingRepo(failWrites: true);
        final c = await seeded(repo, [
          Fragment$MangaDto$meta(key: 'flutter_scanlator', value: 'C'),
        ]);
        final notifier = c.read(
          mangaPreferredScanlatorsProvider(mangaId: 1).notifier,
        );
        final ok = await notifier.setPreference(['B']);
        expect(ok, isFalse);
        // State still reflects the seeded legacy value, not the failed edit.
        expect(c.read(mangaPreferredScanlatorsProvider(mangaId: 1)), ['C']);
      },
    );
  });
}
