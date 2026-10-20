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
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

import 'reader/reader_test_fixtures.dart';

MangaDto _dup() => testManga().copyWith.call(
  id: 2,
  title: 'Solo Leveling',
  author: 'Chugong',
  chapters: Fragment$MangaDto$chapters(totalCount: 12),
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

void main() {
  final candidate = testManga().copyWith.call(id: 1, title: 'Candidate Manga');

  group('single mode', () {
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
  });
}
