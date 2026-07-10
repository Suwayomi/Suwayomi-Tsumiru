// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

GraphQLClient _dummyClient() => GraphQLClient(
      link: HttpLink('http://localhost:0'),
      cache: GraphQLCache(),
    );

class _RecordingRepo extends MangaBookRepository {
  _RecordingRepo() : super(_dummyClient());
  final List<(int, String, dynamic)> patched = [];
  @override
  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async {
    patched.add((mangaId, key, value));
  }
}

/// A manga carrying the given user tags in its meta.
class _TaggedManga extends MangaWithId {
  _TaggedManga(this.tags);
  final List<String> tags;
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
        meta: [
          Fragment$MangaDto$meta(key: 'flutter_tags', value: jsonEncode(tags)),
        ],
        sourceId: '1',
        status: Enum$MangaStatus.ONGOING,
        categories: Fragment$MangaDto$categories(nodes: const []),
        trackRecords:
            Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
        unreadCount: 0,
        updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
        url: '/manga/$mangaId',
      );
}

void main() {
  group('MangaMeta.userTags parse', () {
    test('decodes a JSON string array', () {
      expect(MangaMeta.fromJson({'flutter_tags': '["a","b"]'}).userTags,
          ['a', 'b']);
    });
    test('null on empty / non-JSON / non-list', () {
      expect(MangaMeta.fromJson(const {}).userTags, isNull);
      expect(MangaMeta.fromJson({'flutter_tags': ''}).userTags, isNull);
      expect(MangaMeta.fromJson({'flutter_tags': 'nope'}).userTags, isNull);
      expect(MangaMeta.fromJson({'flutter_tags': '{}'}).userTags, isNull);
    });
  });

  group('mangaUserTagsProvider', () {
    Future<ProviderContainer> seeded(
        _RecordingRepo repo, List<String> tags) async {
      final c = ProviderContainer(overrides: [
        mangaBookRepositoryProvider.overrideWithValue(repo),
        mangaWithIdProvider(mangaId: 1).overrideWith(() => _TaggedManga(tags)),
      ]);
      addTearDown(c.dispose);
      // Resolve the async manga first so the (synchronous) tags provider reads
      // the seeded tags on its first build.
      await c.read(mangaWithIdProvider(mangaId: 1).future);
      expect(c.read(mangaUserTagsProvider(mangaId: 1)), tags);
      return c;
    }

    test('add appends and persists the JSON array', () async {
      final repo = _RecordingRepo();
      final c = await seeded(repo, ['a', 'b']);
      await c.read(mangaUserTagsProvider(mangaId: 1).notifier).add('c');
      expect(repo.patched, contains((1, 'flutter_tags', '["a","b","c"]')));
    });

    test('duplicate and blank tags are ignored (no write)', () async {
      final repo = _RecordingRepo();
      final c = await seeded(repo, ['a', 'b']);
      await c.read(mangaUserTagsProvider(mangaId: 1).notifier).add('a');
      await c.read(mangaUserTagsProvider(mangaId: 1).notifier).add('   ');
      expect(repo.patched, isEmpty);
    });

    test('remove drops the tag and persists', () async {
      final repo = _RecordingRepo();
      final c = await seeded(repo, ['a', 'b']);
      await c.read(mangaUserTagsProvider(mangaId: 1).notifier).remove('a');
      expect(repo.patched, contains((1, 'flutter_tags', '["b"]')));
    });
  });
}
