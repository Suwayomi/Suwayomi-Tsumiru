// Regression coverage for the silent online-progress-loss bug.
//
// Root cause was: graphQlClient + mangaBookRepository were autoDispose, so the
// reader's captured client ref could be torn down mid-write, throwing inside the
// auth link; the throw was then swallowed (no surface, no retry). These tests
// lock the two guarantees the fix restored:
//   1. graphQlClient + mangaBookRepository stay keepAlive (can't be disposed
//      out from under an in-flight write) — the ROOT-CAUSE trip wire.
//   2. A failed online progress push is SURFACED to the caller, never swallowed
//      silently (there is no offline dirty row to retry for an online-only user).

import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';

GraphQLClient _dummyClient() =>
    GraphQLClient(link: HttpLink('http://localhost:0'), cache: GraphQLCache());

/// putChapter throws exactly like the disposed-ref / 401 failure did — the case
/// that used to vanish silently.
class _ThrowingRepository extends MangaBookRepository {
  _ThrowingRepository() : super(_dummyClient());
  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    throw StateError('server component was disposed mid-write');
  }
}

class _OkRepository extends MangaBookRepository {
  _OkRepository() : super(_dummyClient());
  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {}
}

void main() {
  group('root cause: the write path providers must stay keepAlive', () {
    test('graphQlClient is NOT autoDispose', () {
      // If this flips back to @riverpod (autoDispose), the reader can lose its
      // captured client ref mid-write again — the exact regression.
      expect(graphQlClientProvider.isAutoDispose, isFalse);
    });

    test('mangaBookRepository is NOT autoDispose', () {
      expect(mangaBookRepositoryProvider.isAutoDispose, isFalse);
    });
  });

  group('a failed online progress push is surfaced, not swallowed', () {
    test('online-only + failing push -> returns an error (not silently lost)',
        () async {
      final result = await recordReadingProgressWithDependencies(
        offlineEnabled: false, // no dirty row to retry — the online-only case
        offlineDatabase: null,
        repository: _ThrowingRepository(),
        chapterId: 42,
        lastPageRead: 7,
        isRead: false,
      );
      expect(result.hasError, isTrue,
          reason: 'a failed online push must reach the caller so the reader can '
              'show it, instead of vanishing');
    });

    test('online-only + successful push -> no error', () async {
      final result = await recordReadingProgressWithDependencies(
        offlineEnabled: false,
        offlineDatabase: null,
        repository: _OkRepository(),
        chapterId: 42,
        lastPageRead: 7,
        isRead: false,
      );
      expect(result.hasError, isFalse);
    });
  });
}
