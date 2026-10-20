// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      : Fragment$MangaDto$source(
          displayName: sourceName,
          iconUrl: '',
          id: '1',
          contentWarning: Enum$ContentWarning.SAFE,
          lang: 'en',
          name: sourceName,
          $extension: Fragment$MangaDto$source$extension(isObsolete: false),
        ),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: trackerNodes),
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
  });
}
