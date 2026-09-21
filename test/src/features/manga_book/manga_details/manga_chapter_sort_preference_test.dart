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
    trackRecords: Fragment$MangaDto$trackRecords(
      totalCount: 0,
      nodes: const [],
    ),
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
    test(
      'two manga with different webUI_sortBy meta resolve to different '
      'ChapterSort values, independently of each other and of the app-wide '
      'default',
      () async {
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
      },
    );

    test(
      'a manga with no webUI_sortBy meta falls back to the app-wide default, '
      'while a sibling manga with its own meta stays on its own value — '
      'proves the fallback is per-manga, not a single shared resolution',
      () async {
        final repo = _RecordingRepo();
        final c = await _containerFor(repo, {
          1: {'webUI_sortBy': 'source'},
          2: {}, // no per-manga meta at all
        });
        // Set the app-wide default to something distinct from manga 1's
        // per-manga value, so any cross-talk between the two would be
        // visible immediately.
        c.read(mangaChapterSortProvider.notifier).update(ChapterSort.fetchedDate);

        expect(
          c.read(mangaChapterSortPreferenceProvider(mangaId: 1)),
          ChapterSort.source,
          reason: 'manga 1 keeps its own meta regardless of the global value',
        );
        expect(
          c.read(mangaChapterSortPreferenceProvider(mangaId: 2)),
          ChapterSort.fetchedDate,
          reason: 'manga 2 has no override, so it follows the global default',
        );
      },
    );

    test(
      'the Tsumiru-only alphabetical flag takes priority over a stale '
      'webUI_sortBy value for that same manga',
      () async {
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
      },
    );

    test(
      'selecting a WebUI-interoperable axis writes webUI_sortBy AND clears '
      'the alphabetical flag',
      () async {
        final repo = _RecordingRepo();
        final c = await _containerFor(repo, {
          1: {'flutter_chapterSortIsAlphabetical': 'true'},
        });
        await c
            .read(mangaChapterSortPreferenceProvider(mangaId: 1).notifier)
            .update(ChapterSort.uploadDate);

        expect(
          repo.patched,
          contains((1, 'flutter_chapterSortIsAlphabetical', 'false')),
        );
        expect(repo.patched, contains((1, 'webUI_sortBy', 'uploadedAt')));
      },
    );

    test(
      'selecting alphabetical writes ONLY the Tsumiru-own flag, never '
      'touching webUI_sortBy (WebUI has no such mode)',
      () async {
        final repo = _RecordingRepo();
        final c = await _containerFor(repo, {
          1: {'webUI_sortBy': 'source'},
        });
        await c
            .read(mangaChapterSortPreferenceProvider(mangaId: 1).notifier)
            .update(ChapterSort.alphabetical);

        expect(
          repo.patched,
          contains((1, 'flutter_chapterSortIsAlphabetical', 'true')),
        );
        expect(
          repo.patched.where((p) => p.$2 == 'webUI_sortBy'),
          isEmpty,
          reason: 'webUI_sortBy is left untouched so a later switch back to '
              'a real axis has something to fall to',
        );
      },
    );
  });

  group('MangaChapterSortDirectionPreference — per-manga, not global', () {
    test(
      'two manga with different webUI_reverse meta resolve independently, '
      'and a manga with none falls back to the app-wide default',
      () async {
        final repo = _RecordingRepo();
        final c = await _containerFor(repo, {
          1: {'webUI_reverse': 'true'},
          2: {'webUI_reverse': 'false'},
          3: {}, // no per-manga meta
        });
        c.read(mangaChapterSortDirectionProvider.notifier).update(true);

        expect(
          c.read(mangaChapterSortDirectionPreferenceProvider(mangaId: 1)),
          isTrue,
        );
        expect(
          c.read(mangaChapterSortDirectionPreferenceProvider(mangaId: 2)),
          isFalse,
        );
        expect(
          c.read(mangaChapterSortDirectionPreferenceProvider(mangaId: 3)),
          isTrue,
          reason: 'no override -> follows the app-wide default',
        );
      },
    );

    test('update writes the exact WebUI wire string, not a Dart bool', () async {
      final repo = _RecordingRepo();
      final c = await _containerFor(repo, {1: {}});
      await c
          .read(mangaChapterSortDirectionPreferenceProvider(mangaId: 1).notifier)
          .update(true);
      expect(repo.patched, contains((1, 'webUI_reverse', 'true')));
    });
  });
}
