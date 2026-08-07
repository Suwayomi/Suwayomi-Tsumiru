// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/browse_center/domain/source/graphql/__generated__/fragment.graphql.dart'
    show Fragment$SourceDto, Fragment$SourceDto$extension;
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/manga_details/widgets/duplicate_manga_dialog.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'reader/reader_test_fixtures.dart';

MangaDto _dup({
  int id = 2,
  String title = 'Solo Leveling',
  String? author = 'Chugong',
  String? artist,
  int chapterCount = 12,
  int unreadCount = 0,
  Enum$MangaStatus status = Enum$MangaStatus.ONGOING,
  String? sourceName,
  List<Fragment$MangaDto$trackRecords$nodes> trackerNodes = const [],
}) => testManga().copyWith.call(
  id: id,
  title: title,
  author: author,
  artist: artist,
  chapters: Fragment$MangaDto$chapters(totalCount: chapterCount),
  unreadCount: unreadCount,
  status: status,
  source: sourceName == null
      ? null
      : Fragment$SourceDto(
          displayName: sourceName,
          iconUrl: '',
          id: '1',
          isConfigurable: false,
          contentWarning: Enum$ContentWarning.SAFE,
          lang: 'en',
          name: sourceName,
          supportsLatest: false,
          meta: const [],
          $extension: Fragment$SourceDto$extension(
            pkgName: 'test.pkg',
            isObsolete: false,
          ),
        ),
  trackRecords: Fragment$MangaDto$trackRecords(
    totalCount: trackerNodes.length,
    nodes: trackerNodes,
  ),
);

Fragment$MangaDto$trackRecords$nodes _node({
  int trackerId = 1,
  String remoteId = '42',
  String title = 'Solo Leveling',
}) => Fragment$MangaDto$trackRecords$nodes(
  id: 1,
  trackerId: trackerId,
  remoteId: remoteId,
  status: 1,
  score: 0,
  title: title,
);

class _Harness extends StatefulWidget {
  const _Harness({required this.builder, required this.onResult});
  final WidgetBuilder builder;
  final ValueChanged<DuplicateDialogResult?> onResult;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await showDialog<DuplicateDialogResult>(
              context: context,
              builder: widget.builder,
            );
            widget.onResult(result);
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

Future<DuplicateDialogResult?> _pumpAndOpen(
  WidgetTester tester, {
  required WidgetBuilder builder,
}) async {
  DuplicateDialogResult? result;
  var resolved = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Harness(
        builder: builder,
        onResult: (r) {
          result = r;
          resolved = true;
        },
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // Callers assert on `result` after driving their own button/card taps;
  // stash resolution state via the closure above.
  return resolved ? result : null;
}

void main() {
  final candidate = testManga().copyWith.call(id: 1, title: 'Candidate Manga');

  group('single mode', () {
    testWidgets('renders title, body and duplicate card fields', (
      tester,
    ) async {
      final dup = _dup(sourceName: 'MangaDex');
      await _pumpAndOpen(
        tester,
        builder: (_) => DuplicateMangaDialog(
          candidate: candidate,
          duplicates: [dup],
          certainIds: const {},
          trackerNameOf: (_) => null,
        ),
      );

      expect(find.text('Possible duplicates'), findsOneWidget);
      expect(find.text(candidate.title), findsOneWidget);
      expect(
        find.text(
          'You have entries in your library with a similar name.\n\n'
          'Select an entry to migrate or add anyway.',
        ),
        findsOneWidget,
      );
      expect(find.text(dup.title), findsOneWidget);
      expect(find.text('Chugong'), findsOneWidget);
      expect(find.textContaining('12'), findsOneWidget);
      expect(find.text('MangaDex'), findsOneWidget);
    });

    testWidgets('Add anyway pops addAnyway', (tester) async {
      DuplicateDialogResult? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _Harness(
            builder: (_) => DuplicateMangaDialog(
              candidate: candidate,
              duplicates: [_dup()],
              certainIds: const {},
              trackerNameOf: (_) => null,
            ),
            onResult: (r) => result = r,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add anyway'));
      await tester.pumpAndSettle();

      expect(result, DuplicateDialogResult.addAnyway);
    });

    testWidgets('Cancel pops cancel', (tester) async {
      DuplicateDialogResult? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _Harness(
            builder: (_) => DuplicateMangaDialog(
              candidate: candidate,
              duplicates: [_dup()],
              certainIds: const {},
              trackerNameOf: (_) => null,
            ),
            onResult: (r) => result = r,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, DuplicateDialogResult.cancel);
    });

    testWidgets('card tap awaits onMigrate and pops migrated only on true', (
      tester,
    ) async {
      DuplicateDialogResult? result;
      var shouldMigrate = false;
      final dup = _dup();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _Harness(
            builder: (_) => DuplicateMangaDialog(
              candidate: candidate,
              duplicates: [dup],
              certainIds: const {},
              trackerNameOf: (_) => null,
              onMigrate: (_) async => shouldMigrate,
            ),
            onResult: (r) => result = r,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // false: onMigrate declines, dialog stays open.
      await tester.tap(find.text(dup.title));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text(dup.title), findsOneWidget);

      // true: onMigrate accepts, dialog pops migrated.
      shouldMigrate = true;
      await tester.tap(find.text(dup.title));
      await tester.pumpAndSettle();
      expect(result, DuplicateDialogResult.migrated);
    });

    testWidgets('card tap falls back to openedEntry when onMigrate is null', (
      tester,
    ) async {
      DuplicateDialogResult? result;
      MangaDto? opened;
      final dup = _dup();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _Harness(
            builder: (_) => DuplicateMangaDialog(
              candidate: candidate,
              duplicates: [dup],
              certainIds: const {},
              trackerNameOf: (_) => null,
              onOpenEntry: (m) => opened = m,
            ),
            onResult: (r) => result = r,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(dup.title));
      await tester.pumpAndSettle();

      expect(result, DuplicateDialogResult.openedEntry);
      expect(opened?.id, dup.id);
    });

    testWidgets(
      'long-press invokes onOpenEntry with the duplicate and pops openedEntry',
      (tester) async {
        DuplicateDialogResult? result;
        MangaDto? opened;
        final dup = _dup();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: _Harness(
              builder: (_) => DuplicateMangaDialog(
                candidate: candidate,
                duplicates: [dup],
                certainIds: const {},
                trackerNameOf: (_) => null,
                onMigrate: (_) async => true,
                onOpenEntry: (m) => opened = m,
              ),
              onResult: (r) => result = r,
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.longPress(find.text(dup.title));
        await tester.pumpAndSettle();

        expect(result, DuplicateDialogResult.openedEntry);
        expect(opened?.id, dup.id);
      },
    );
  });

  group('certain-tracker chip', () {
    testWidgets('renders named chip when trackerNameOf resolves', (
      tester,
    ) async {
      final dup = _dup(trackerNodes: [_node(trackerId: 3)]);
      await _pumpAndOpen(
        tester,
        builder: (_) => DuplicateMangaDialog(
          candidate: candidate.copyWith.call(
            trackRecords: Fragment$MangaDto$trackRecords(
              totalCount: 1,
              nodes: [_node(trackerId: 3)],
            ),
          ),
          duplicates: [dup],
          certainIds: {dup.id},
          trackerNameOf: (id) => id == 3 ? 'AniList' : null,
        ),
      );

      expect(find.text('Same AniList entry'), findsOneWidget);
    });

    testWidgets('renders generic chip when trackerNameOf returns null', (
      tester,
    ) async {
      final dup = _dup(trackerNodes: [_node(trackerId: 3)]);
      await _pumpAndOpen(
        tester,
        builder: (_) => DuplicateMangaDialog(
          candidate: candidate.copyWith.call(
            trackRecords: Fragment$MangaDto$trackRecords(
              totalCount: 1,
              nodes: [_node(trackerId: 3)],
            ),
          ),
          duplicates: [dup],
          certainIds: {dup.id},
          trackerNameOf: (_) => null,
        ),
      );

      expect(find.text('Same tracker entry'), findsOneWidget);
    });

    testWidgets('no chip when the duplicate is not tracker-certain', (
      tester,
    ) async {
      final dup = _dup();
      await _pumpAndOpen(
        tester,
        builder: (_) => DuplicateMangaDialog(
          candidate: candidate,
          duplicates: [dup],
          certainIds: const {},
          trackerNameOf: (_) => 'AniList',
        ),
      );

      expect(find.text('Same AniList entry'), findsNothing);
      expect(find.text('Same tracker entry'), findsNothing);
    });
  });

  group('bulk mode', () {
    testWidgets('shows all six buttons', (tester) async {
      await _pumpAndOpen(
        tester,
        builder: (_) => DuplicateMangaDialog(
          candidate: candidate,
          duplicates: [_dup()],
          certainIds: const {},
          trackerNameOf: (_) => null,
          bulk: true,
        ),
      );

      expect(find.text('Add anyway'), findsOneWidget);
      expect(find.text('Allow all'), findsOneWidget);
      expect(find.text('Skip it'), findsOneWidget);
      expect(find.text('Skip all'), findsOneWidget);
      expect(find.text('Show entry'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    for (final entry in {
      'Allow all': DuplicateDialogResult.allowAll,
      'Skip it': DuplicateDialogResult.skipIt,
      'Skip all': DuplicateDialogResult.skipAll,
    }.entries) {
      testWidgets('${entry.key} pops ${entry.value}', (tester) async {
        DuplicateDialogResult? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: _Harness(
              builder: (_) => DuplicateMangaDialog(
                candidate: candidate,
                duplicates: [_dup()],
                certainIds: const {},
                trackerNameOf: (_) => null,
                bulk: true,
              ),
              onResult: (r) => result = r,
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();

        expect(result, entry.value);
      });
    }

    testWidgets('Show entry invokes onOpenEntry with the candidate', (
      tester,
    ) async {
      DuplicateDialogResult? result;
      MangaDto? opened;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _Harness(
            builder: (_) => DuplicateMangaDialog(
              candidate: candidate,
              duplicates: [_dup()],
              certainIds: const {},
              trackerNameOf: (_) => null,
              bulk: true,
              onOpenEntry: (m) => opened = m,
            ),
            onResult: (r) => result = r,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show entry'));
      await tester.pumpAndSettle();

      expect(result, DuplicateDialogResult.openedEntry);
      expect(opened?.id, candidate.id);
    });
  });
}
