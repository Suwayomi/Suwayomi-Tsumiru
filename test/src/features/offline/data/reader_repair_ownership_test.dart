import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/offline/data/background/background_download_controller.dart';
import 'package:tsumiru/src/features/offline/data/offline_database.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/features/offline/data/offline_paths.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';

import '../../../../helpers/fake_page_store.dart';
import '../../../../helpers/offline_test_db.dart';

class _OnlinePages implements MangaBookRepository {
  int requests = 0;

  @override
  Future<ChapterPagesDto?> getChapterPages({required int chapterId}) async {
    requests++;
    return ChapterPagesDto(
      chapter: ChapterPagesChapterDto(id: chapterId, pageCount: 1),
      pages: ['/online.jpg'],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReaderOwnership extends BackgroundDownloadController {
  _ReaderOwnership(super.ref);
  int acquisitions = 0;

  @override
  Future<T> withOwnership<T>(Future<T> Function() action) async {
    acquisitions++;
    return action();
  }
}

void main() {
  for (final state in [
    OfflineDeviceState.none,
    OfflineDeviceState.queued,
    OfflineDeviceState.downloaded,
  ]) {
    test(
      'opening ${state.name} chapter only takes ownership when repair is needed',
      () async {
        final db = testOfflineDatabase();
        addTearDown(db.close);
        await db.upsertChapterMetadata(
          id: 5,
          mangaId: 1,
          name: 'Chapter',
          chapterIndex: 0,
          isRead: false,
          lastPageRead: 0,
          isBookmarked: false,
          serverIsDownloaded: true,
          pageCount: 1,
          updatedAt: DateTime(2026),
        );
        await db.setChapterDeviceState(5, state);
        final online = _OnlinePages();
        final store = FakePageStore();
        const paths = OfflinePaths('/tmp/reader-repair-test');
        var starts = 0;
        late _ReaderOwnership ownership;
        final container = ProviderContainer(
          overrides: [
            offlineReadDatabaseProvider.overrideWithValue(db),
            offlineRepositoryProvider.overrideWithValue(
              OfflineRepository(db: db, paths: paths),
            ),
            offlinePageStoreProvider.overrideWithValue(store),
            offlinePathsProvider.overrideWithValue(paths),
            mangaBookRepositoryProvider.overrideWithValue(online),
            backgroundDownloadControllerProvider.overrideWith(
              (ref) => ownership = _ReaderOwnership(ref),
            ),
            downloadStarterProvider.overrideWithValue(({
              bool userInitiated = false,
            }) async {
              starts++;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(backgroundDownloadControllerProvider);
        final subscription = container.listen(
          chapterPagesProvider(chapterId: 5),
          (_, _) {},
        );
        addTearDown(subscription.close);
        final result = await container.read(
          chapterPagesProvider(chapterId: 5).future,
        );
        expect(result!.pages, ['/online.jpg']);
        expect(online.requests, 1);
        final repaired = state == OfflineDeviceState.downloaded;
        expect(ownership.acquisitions, repaired ? 1 : 0);
        expect(starts, repaired ? 1 : 0);
        final row = (await db.chapterById(5))!;
        expect(row.deviceState, repaired ? OfflineDeviceState.queued : state);
        expect(row.downloadGeneration, repaired ? 1 : 0);
      },
    );
  }
}
