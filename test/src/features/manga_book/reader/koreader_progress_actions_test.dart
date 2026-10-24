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
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

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

void main() {
  for (final remotePage in [1, 2]) {
    testWidgets('accepting page ${remotePage + 1} saves progress and jumps', (
      tester,
    ) async {
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
                    remotePage: remotePage,
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
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(jumpedTo, remotePage);
      expect(repository.writes, hasLength(1));
      expect(
        repository.writes.single.lastPageRead,
        remotePage == 2 ? 0 : remotePage,
      );
      if (remotePage == 2) expect(repository.writes.single.isRead, true);
    });
  }

  testWidgets('declining the remote location leaves the reader on its page', (
    tester,
  ) async {
    var jumps = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          viewOfflineNowProvider.overrideWithValue(false),
          serverUnreachableProvider.overrideWithValue(false),
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
                  remotePage: 1,
                  deviceName: 'KOReader',
                  onJump: (_) => jumps++,
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
    expect(find.text("Sync to page 2 from device 'KOReader'?"), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(jumps, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('offline progress checks show no prompt or jump', (tester) async {
    var jumps = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [viewOfflineNowProvider.overrideWithValue(true)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => applyKoSyncConflict(
                  context: context,
                  ref: ref,
                  chapter: testChapter(),
                  remotePage: 1,
                  deviceName: 'KOReader',
                  onJump: (_) => jumps++,
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
    expect(jumps, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('retry all invokes every registered page reload', (tester) async {
    var retries = 0;
    late WidgetRef readerRef;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (_, ref, _) {
            readerRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    readerRef.read(failedReaderPageReloadsProvider).addAll([
      () async {
        retries++;
      },
      () async {
        retries++;
      },
    ]);
    await retryFailedReaderPages(readerRef);
    expect(retries, 2);
  });
}
