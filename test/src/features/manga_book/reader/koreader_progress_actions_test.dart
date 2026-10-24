import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/features/auth/data/auth_credentials_store.dart';
import 'package:tsumiru/src/features/manga_book/data/manga_book/manga_book_repository.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_batch/chapter_batch_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/koreader_progress_actions.dart';
import 'package:tsumiru/src/features/offline/data/offline_repository.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'reader_test_fixtures.dart';

class _Session extends AuthCredentialsStore {
  @override
  Future<AuthCredentialsState> build() async => const AuthCredentialsState();
}

class _ProgressRepository extends MangaBookRepository {
  _ProgressRepository()
    : super(
        GraphQLClient(
          link: HttpLink('http://localhost:0'),
          cache: GraphQLCache(),
        ),
      );
  final writes = <ChapterChange>[];
  @override
  Future<void> putChapter({
    required int chapterId,
    required ChapterChange patch,
  }) async {
    writes.add(patch);
  }
}

class _Chapters extends MangaChapterList {
  @override
  Future<List<ChapterDto>?> build({required int mangaId}) async => [
    testChapter(),
  ];
}

class _KoRepository implements KoreaderSyncRepository {
  _KoRepository(this.progress);
  final _ProgressRepository progress;
  int pushes = 0;

  @override
  Future<void> pushProgress(int chapterId) async {
    expect(chapterId, 1);
    expect(progress.writes, hasLength(1));
    expect(progress.writes.single.lastPageRead, 2);
    expect(progress.writes.single.isRead, isTrue);
    pushes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('final-page KOReader push preserves the true last page', (
    tester,
  ) async {
    final progress = _ProgressRepository();
    final koReader = _KoRepository(progress);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          viewOfflineNowProvider.overrideWithValue(false),
          serverUnreachableProvider.overrideWithValue(false),
          offlineActiveProvider.overrideWithValue(false),
          authCredentialsStoreProvider.overrideWith(_Session.new),
          mangaBookRepositoryProvider.overrideWithValue(progress),
          mangaChapterListProvider(mangaId: 1).overrideWith(_Chapters.new),
          koreaderSyncRepositoryProvider.overrideWithValue(koReader),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => syncKoReaderChapter(
                context: context,
                ref: ref,
                chapter: testChapter(),
                push: true,
                currentPage: 2,
                pageCount: 3,
              ),
              child: const Text('Push'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(koReader.pushes, 1);
    expect(progress.writes.single.lastPageRead, 2);
  });

  testWidgets(
    'KOReader conflict decline preserves progress and accept saves it',
    (tester) async {
      final repository = _ProgressRepository();
      int? jumpedTo;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            viewOfflineNowProvider.overrideWithValue(false),
            serverUnreachableProvider.overrideWithValue(false),
            offlineActiveProvider.overrideWithValue(false),
            authCredentialsStoreProvider.overrideWith(_Session.new),
            mangaBookRepositoryProvider.overrideWithValue(repository),
            mangaChapterListProvider(mangaId: 1).overrideWith(_Chapters.new),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => applyKoSyncConflict(
                    context: context,
                    ref: ref,
                    chapter: testChapter(),
                    remotePage: 2,
                    deviceName: 'KOReader',
                    onJump: (page) => jumpedTo = page,
                  ),
                  child: const Text('Check'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(jumpedTo, isNull);
      expect(repository.writes, isEmpty);

      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(jumpedTo, 2);
      expect(repository.writes, hasLength(1));
      expect(repository.writes.single.lastPageRead, 2);
      expect(repository.writes.single.isRead, isTrue);
    },
  );
}
