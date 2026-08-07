// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';

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

class _FakeMangaWithId extends MangaWithId {
  @override
  Future<MangaDto?> build({required int mangaId}) async => null;
}

void main() {
  group('MangaMeta.rating', () {
    test('parses an int from the string-backed meta value', () {
      expect(MangaMeta.fromJson({'flutter_rating': '4'}).rating, 4);
    });
    test('is null when absent or unparseable', () {
      expect(MangaMeta.fromJson(const {}).rating, isNull);
      expect(MangaMeta.fromJson({'flutter_rating': 'x'}).rating, isNull);
    });
  });

  group('mangaRatingProvider', () {
    test('unrated manga reads 0', () {
      final c = ProviderContainer(overrides: [
        mangaWithIdProvider(mangaId: 1).overrideWith(() => _FakeMangaWithId()),
      ]);
      addTearDown(c.dispose);
      expect(c.read(mangaRatingProvider(mangaId: 1)), 0);
    });

    test('update persists the clamped rating to the meta store', () async {
      final repo = _RecordingRepo();
      final c = ProviderContainer(overrides: [
        mangaBookRepositoryProvider.overrideWithValue(repo),
        mangaWithIdProvider(mangaId: 1).overrideWith(() => _FakeMangaWithId()),
      ]);
      addTearDown(c.dispose);

      await c.read(mangaRatingProvider(mangaId: 1).notifier).update(3);
      expect(repo.patched, contains((1, 'flutter_rating', '3')));

      // Out-of-range is clamped to 0..5.
      await c.read(mangaRatingProvider(mangaId: 1).notifier).update(9);
      expect(repo.patched, contains((1, 'flutter_rating', '5')));

      // Clearing (0) is a valid write.
      await c.read(mangaRatingProvider(mangaId: 1).notifier).update(0);
      expect(repo.patched, contains((1, 'flutter_rating', '0')));
    });
  });
}
