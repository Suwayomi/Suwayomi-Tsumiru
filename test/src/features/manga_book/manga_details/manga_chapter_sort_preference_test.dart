// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Proves the chapter sort setting is now resolved PER MANGA (via the
// server's per-manga meta store, same convention WebUI itself uses) rather
// than the single app-wide setting it used to be exclusively driven by.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

class _RecordingRepo extends MangaBookRepository {
  _RecordingRepo({this.fail = false}) : super(_dummyClient());

  /// Simulates an unreachable server: every meta write throws.
  final bool fail;
  final List<(int, String, dynamic)> patched = [];
  final List<(int, String)> deleted = [];
  @override
  Future<void> patchMangaMeta({
    required int mangaId,
    required String key,
    required dynamic value,
  }) async {
    if (fail) throw Exception('server unreachable');
    patched.add((mangaId, key, value));
  }

  @override
  Future<void> deleteMangaMeta({
    required int mangaId,
    required String key,
  }) async {
    if (fail) throw Exception('server unreachable');
    deleted.add((mangaId, key));
  }
}

/// A manga carrying the given raw meta entries — mirrors what a live sync
/// (or WebUI itself) would have written into MangaDto.meta.
class _MetaManga extends MangaWithId {
  _MetaManga(this.meta);
  final Map<String, String> meta;
  @override
  Future<MangaDto?> build({required int mangaId}) async => Fragment$MangaDto(
    id: mangaId,
    title: 'M$mangaId',
    bookmarkCount: 0,
    chapters: Fragment$MangaDto$chapters(totalCount: 0),
    downloadCount: 0,
    genre: const [],
    inLibrary: true,
    inLibraryAt: '0',
    initialized: true,
    meta: [
      for (final e in meta.entries)
        Fragment$MangaDto$meta(key: e.key, value: e.value),
    ],
    sourceId: '1',
    status: Enum$MangaStatus.ONGOING,
    categories: Fragment$MangaDto$categories(nodes: const []),
    trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
    unreadCount: 0,
    updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
    url: '/manga/$mangaId',
  );
}

Future<ProviderContainer> _containerFor(
  _RecordingRepo repo,
  Map<int, Map<String, String>> mangaMetaById,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      mangaBookRepositoryProvider.overrideWithValue(repo),
      for (final entry in mangaMetaById.entries)
        mangaWithIdProvider(
          mangaId: entry.key,
        ).overrideWith(() => _MetaManga(entry.value)),
    ],
  );
  addTearDown(c.dispose);
  for (final id in mangaMetaById.keys) {
    await c.read(mangaWithIdProvider(mangaId: id).future);
  }
  return c;
}

void main() {
  group('MangaChapterSortPreference — per-manga, not global', () {
    test('two manga with different webUI_sortBy meta resolve to different '
        'ChapterSort values, independently of each other and of the app-wide '
        'default', () async {
      final repo = _RecordingRepo();
      final c = await _containerFor(repo, {
        1: {'webUI_sortBy': 'uploadedAt'},
        2: {'webUI_sortBy': 'chapterNumber'},
      });

      expect(
        c.read(mangaChapterSortPreferenceProvider(mangaId: 1)),
        ChapterSort.uploadDate,
      );
      expect(
        c.read(mangaChapterSortPreferenceProvider(mangaId: 2)),
        ChapterSort.chapterNumber,
      );
    });

    test('the Tsumiru-only alphabetical flag takes priority over a stale '
        'webUI_sortBy value for that same manga', () async {
      final repo = _RecordingRepo();
      final c = await _containerFor(repo, {
        1: {
          'flutter_chapterSortIsAlphabetical': 'true',
          'webUI_sortBy': 'chapterNumber',
        },
      });
      expect(
        c.read(mangaChapterSortPreferenceProvider(mangaId: 1)),
        ChapterSort.alphabetical,
      );
    });

    test(
      'selecting a WebUI-interoperable axis writes webUI_sortBy AND deletes '
      'the alphabetical flag (rather than leaving a "false" behind)',
      () async {
        final repo = _RecordingRepo();
        final c = await _containerFor(repo, {
          1: {'flutter_chapterSortIsAlphabetical': 'true'},
        });
        await c
            .read(mangaChapterSortPreferenceProvider(mangaId: 1).notifier)
            .update(ChapterSort.uploadDate);

        expect(repo.deleted, [(1, 'flutter_chapterSortIsAlphabetical')]);
        expect(
          repo.patched.where(
            (p) => p.$2 == 'flutter_chapterSortIsAlphabetical',
          ),
          isEmpty,
        );
        expect(repo.patched, contains((1, 'webUI_sortBy', 'uploadedAt')));
      },
    );

    test('a failed write (server unreachable) is returned as an error and does '
        'NOT change the displayed sort', () async {
      final repo = _RecordingRepo(fail: true);
      final c = await _containerFor(repo, {
        1: {'webUI_sortBy': 'source'},
      });
      final result = await c
          .read(mangaChapterSortPreferenceProvider(mangaId: 1).notifier)
          .update(ChapterSort.alphabetical);

      expect(result.hasError, isTrue);
      await c.read(mangaWithIdProvider(mangaId: 1).future);
      expect(
        c.read(mangaChapterSortPreferenceProvider(mangaId: 1)),
        ChapterSort.source,
      );
    });
  });

  group('MangaChapterSortDirectionPreference — per-manga, not global', () {
    test('update writes the exact WebUI wire string, inverted: ascending is '
        'webUI_reverse "false", descending is "true"', () async {
      final repo = _RecordingRepo();
      final c = await _containerFor(repo, {1: {}});
      final notifier = c.read(
        mangaChapterSortDirectionPreferenceProvider(mangaId: 1).notifier,
      );
      await notifier.update(true);
      await notifier.update(false);
      expect(repo.patched, [
        (1, 'webUI_reverse', 'false'),
        (1, 'webUI_reverse', 'true'),
      ]);
    });
  });
}
