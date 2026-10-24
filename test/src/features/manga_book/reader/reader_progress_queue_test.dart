import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/controller/manga_details_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/utils/reader_progress_queue.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_wrapper.dart';
import 'package:tsumiru/src/features/settings/presentation/koreader_sync/data/graphql/__generated__/koreader_sync.graphql.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'reader_test_fixtures.dart';

void main() {
  testWidgets(
    'pull waits for an active save and supersedes buffered progress',
    (tester) async {
      final queue = ReaderProgressQueue();
      final pending = Completer<void>();
      final events = <String>[];
      final oldGeneration = queue.generation;
      final save = queue.run(() async {
        await pending.future;
        events.add('save');
      });
      final pull = queue.pull(() async {
        events.add('pull');
        return 42;
      });
      expect(queue.syncing, isTrue);
      expect(queue.generation, oldGeneration);
      pending.complete();
      await save;
      expect(await pull, 42);
      expect(queue.generation, isNot(oldGeneration));
      expect(events, ['save', 'pull']);
      expect(queue.syncing, isFalse);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final remote =
          Completer<Mutation$PullKoSyncProgress$pullKoSyncProgress?>();
      int? jumpedTo;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            localKoSyncProgressProvider(
              chapterId: 1,
            ).overrideWith((ref) => remote.future),
            chapterProvider(
              chapterId: 1,
            ).overrideWithBuild((ref, _) => testChapter()),
            getNextAndPreviousChaptersProvider(
              mangaId: 1,
              chapterId: 1,
            ).overrideWithValue((first: null, second: null)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ReaderWrapper(
              manga: testManga(),
              chapter: testChapter(),
              chapterPages: ChapterPagesDto(
                chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
                pages: const ['a', 'b', 'c'],
              ),
              currentIndex: 0,
              onChanged: (page) => jumpedTo = page,
              onNext: () {},
              onPrevious: () {},
              scrollDirection: Axis.horizontal,
              effectiveReaderMode: ReaderMode.singleHorizontalLTR,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();
      remote.complete(
        Mutation$PullKoSyncProgress$pullKoSyncProgress(
          chapter: testChapter().copyWith.call(
            user: testChapter().user.copyWith.call(lastPageRead: 2),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(jumpedTo, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
