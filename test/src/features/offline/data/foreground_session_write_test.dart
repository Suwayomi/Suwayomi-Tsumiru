import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_dto_mappers.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/offline_runtime_storage.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

import '../../../../helpers/offline_test_db.dart';

class _Repository extends MangaBookRepository {
  _Repository()
    : super(
        GraphQLClient(
          cache: GraphQLCache(),
          link: Link.function((request, [forward]) => const Stream.empty()),
        ),
      );
  final started = Completer<void>();
  final release = Completer<void>();
  int puts = 0;
  int batches = 0;
  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    puts++;
    started.complete();
    await release.future;
  }

  @override
  Future<void> modifyBulkChapters(ChapterBatch batch) async {
    batches++;
    if (!started.isCompleted) started.complete();
    await release.future;
  }
}

class _Chapters extends MangaChapterList {
  _Chapters(this.chapters);
  final List<ChapterDto> chapters;
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => chapters;
}

class _Preferred extends MangaPreferredScanlators {
  @override
  List<String> build({required int mangaId}) => ['A'];
}

void main() {
  for (final operation in ['progress', 'bookmark', 'read batch']) {
    testWidgets(
      '$operation cannot acknowledge or write into B after switching from A',
      (tester) async {
        await tester.runAsync(() async {
          FlutterSecureStorage.setMockInitialValues({});
          SharedPreferences.setMockInitialValues({});
          final preferences = await SharedPreferences.getInstance();
          final a = testOfflineDatabase();
          final b = testOfflineDatabase();
          for (final db in [a, b]) {
            for (final id in [1, 2]) {
              await db.upsertChapterMetadata(
                id: id,
                mangaId: 1,
                name: 'Chapter',
                chapterIndex: id,
                chapterNumber: 1,
                isRead: false,
                lastPageRead: 0,
                isBookmarked: false,
                serverIsDownloaded: true,
                pageCount: 4,
                updatedAt: DateTime(2026),
              );
            }
          }
          final chapters = [
            for (final id in [1, 2])
              offlineChapterToDto(
                (await a.chapterById(id))!,
              ).copyWith(scanlator: id == 1 ? 'A' : 'B'),
          ];
          final first = _Repository();
          final second = _Repository();
          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              offlineActiveProvider.overrideWithValue(true),
              offlineDatabaseProvider.overrideWithValue(a),
              mangaBookRepositoryProvider.overrideWithValue(first),
              mangaChapterListProvider.overrideWith2(
                (_) => _Chapters(chapters),
              ),
              mangaPreferredScanlatorsProvider.overrideWith2(
                (_) => _Preferred(),
              ),
            ],
          );
          await container.read(authCredentialsStoreProvider.future);
          await container.read(mangaChapterListProvider(mangaId: 1).future);
          late WidgetRef ref;
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: Consumer(
                builder: (context, widgetRef, child) {
                  ref = widgetRef;
                  return const SizedBox();
                },
              ),
            ),
          );
          final work = switch (operation) {
            'progress' => recordReadingProgress(
              ref,
              mangaId: 1,
              chapterId: 1,
              lastPageRead: 3,
              isRead: true,
            ),
            'bookmark' => recordBookmark(ref, chapterId: 1, isBookmarked: true),
            _ => recordReadState(ref, chapterIds: [1, 2], isRead: true),
          };
          await first.started.future;
          var drained = false;
          final drain = container
              .read(offlineRuntimeStorageProvider.notifier)
              .drain()
              .then((_) => drained = true);
          await Future<void>.delayed(Duration.zero);
          expect(drained, isFalse);
          await container
              .read(authCredentialsStoreProvider.notifier)
              .withIdentityChange(() async {});
          container.updateOverrides([
            sharedPreferencesProvider.overrideWithValue(preferences),
            offlineActiveProvider.overrideWithValue(true),
            offlineDatabaseProvider.overrideWithValue(b),
            mangaBookRepositoryProvider.overrideWithValue(second),
            mangaChapterListProvider.overrideWith2((_) => _Chapters(chapters)),
            mangaPreferredScanlatorsProvider.overrideWith2((_) => _Preferred()),
          ]);
          first.release.complete();
          await work;
          await drain;
          expect(second.puts, 0);
          expect(second.batches, 0);
          // Completing a chapter that has hidden scanlator copies writes all of
          // them in ONE batch on the session that started the read, so the
          // batch belongs to A and never re-runs against B.
          if (operation == 'progress') expect(first.batches, 1);
          for (final id in [1, 2]) {
            final row = (await b.chapterById(id))!;
            expect(row.isRead, isFalse);
            expect(row.lastPageRead, 0);
            expect(row.isBookmarked, isFalse);
          }
          final local = (await a.chapterById(1))!;
          expect(
            operation == 'bookmark'
                ? local.bookmarkDirty
                : local.readStateDirty,
            isTrue,
          );
          await tester.pumpWidget(const SizedBox());
          container.dispose();
          await a.close();
          await b.close();
        });
      },
    );
  }
}
