// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/widgets/chapter_actions/chapter_bulk_actions.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../../helpers/offline_test_db.dart';

class _UnreachableBook extends MangaBookRepository {
  _UnreachableBook()
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
      );

  final puts = <({int id, ChapterChange patch})>[];

  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    puts.add((id: chapterId, patch: patch));
    throw Exception('server unreachable');
  }
}

class _Session extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async =>
      const AuthCredentialsState.empty();
}

void main() {
  testWidgets(
    'bulk bookmark writes locally and stays queued when the server fails',
    (tester) async {
      await tester.runAsync(() async {
        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final db = testOfflineDatabase();
        for (final id in [1, 2]) {
          await db.upsertChapterMetadata(
            id: id,
            mangaId: 1,
            name: 'Chapter $id',
            chapterIndex: id,
            chapterNumber: id.toDouble(),
            isRead: false,
            lastPageRead: 0,
            isBookmarked: false,
            serverIsDownloaded: true,
            pageCount: 4,
            updatedAt: DateTime(2026),
          );
        }
        final book = _UnreachableBook();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            offlineActiveProvider.overrideWithValue(true),
            offlineDatabaseProvider.overrideWithValue(db),
            mangaBookRepositoryProvider.overrideWithValue(book),
            authCredentialsStoreProvider.overrideWith(_Session.new),
          ],
        );
        await container.read(authCredentialsStoreProvider.future);
        late WidgetRef ref;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Consumer(
                builder: (context, widgetRef, child) {
                  ref = widgetRef;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        final chapters = [
          for (final id in [1, 2])
            offlineChapterToDto((await db.chapterById(id))!),
        ];
        await setChaptersBookmark(
          ref: ref,
          chapters: chapters,
          isBookmarked: true,
          refresh: (_) async {},
        );

        // The local catalogue is authoritative; the failed push leaves the
        // rows dirty for the next sync.
        for (final id in [1, 2]) {
          final row = (await db.chapterById(id))!;
          expect(row.isBookmarked, isTrue, reason: 'chapter $id local');
          expect(row.bookmarkDirty, isTrue, reason: 'chapter $id dirty');
        }
        expect([for (final p in book.puts) p.id], [1, 2]);
        expect(book.puts.every((p) => p.patch.isBookmarked == true), isTrue);

        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await db.close();
      });
    },
  );
}
