// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/domain/duplicate_matcher.dart';
import 'package:tsumiru/src/features/library/presentation/duplicates/controller/library_duplicates_controller.dart';
import 'package:tsumiru/src/features/library/presentation/duplicates/library_duplicates_screen.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/manga_cover/grid/manga_cover_grid_tile.dart';
import 'package:tsumiru/src/widgets/selection_action_bar.dart';

import '../manga_book/reader/reader_test_fixtures.dart';

MangaDto _m(int id, String title) =>
    testManga().copyWith.call(id: id, title: title);

class _FixedUnreachable extends ServerUnreachable {
  @override
  bool build() => true;
}

/// Stubs the scan result and counts how many times the provider (re)built, so a
/// test can prove a removal never re-triggers the scan.
class _FakeLibraryDuplicates extends LibraryDuplicates {
  _FakeLibraryDuplicates(this._groups, this._buildCount);
  final List<DupGroup> _groups;
  final List<int> _buildCount;
  @override
  Future<List<DupGroup>> build({required bool checkDescriptions}) async {
    _buildCount[0]++;
    return _groups;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required List<MangaDto> library,
  required List<DupGroup> groups,
  required DuplicateEntryRemover remover,
  List<int>? buildCount,
  bool offline = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final client = GraphQLClient(
    link: HttpLink('http://localhost'),
    cache: GraphQLCache(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        graphQlClientProvider.overrideWithValue(client),
        libraryMangaListProvider.overrideWith((ref) async => library),
        libraryTrackerNamesProvider.overrideWithValue(const {}),
        libraryDuplicatesProvider(
          checkDescriptions: false,
        ).overrideWith(() => _FakeLibraryDuplicates(groups, buildCount ?? [0])),
        duplicateEntryRemoverProvider.overrideWithValue(remover),
        if (offline)
          serverUnreachableProvider.overrideWith(_FixedUnreachable.new),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LibraryDuplicatesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Long-press the [index]-th cover to enter/extend the selection.
Future<void> _longPressCover(WidgetTester tester, int index) async {
  await tester.longPress(find.byType(MangaCoverGridTile).at(index));
  await tester.pumpAndSettle();
}

void main() {
  group('multi-select remove', () {
    testWidgets('confirm dialog states the live selected count', (
      tester,
    ) async {
      final calls = <int>[];
      await _pump(
        tester,
        library: [_m(1, 'A'), _m(2, 'A')],
        groups: const [
          (header: 'A', memberIds: [1, 2], reasons: {DupReason.title}),
        ],
        remover: (ref, id) async => calls.add(id),
      );

      await _longPressCover(tester, 0);
      await _longPressCover(tester, 1);
      expect(find.byType(SelectionActionBar), findsOneWidget);

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Remove 2 entries from your library? '
          'This also deletes downloaded chapters on this device.',
        ),
        findsOneWidget,
      );
      expect(calls, isEmpty); // dialog only; nothing removed yet
    });

    testWidgets('cancel is a no-op — nothing removed, group intact', (
      tester,
    ) async {
      final calls = <int>[];
      await _pump(
        tester,
        library: [_m(1, 'A'), _m(2, 'A')],
        groups: const [
          (header: 'A', memberIds: [1, 2], reasons: {DupReason.title}),
        ],
        remover: (ref, id) async => calls.add(id),
      );

      await _longPressCover(tester, 0);
      await _longPressCover(tester, 1);
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
      expect(find.byType(MangaCoverGridTile), findsNWidgets(2));
    });

    testWidgets('confirming removes all: group drops below two and disappears, '
        'no rescan', (tester) async {
      final calls = <int>[];
      final buildCount = [0];
      await _pump(
        tester,
        library: [_m(1, 'A'), _m(2, 'A')],
        groups: const [
          (header: 'A', memberIds: [1, 2], reasons: {DupReason.title}),
        ],
        remover: (ref, id) async => calls.add(id),
        buildCount: buildCount,
      );

      expect(buildCount[0], 1);

      await _longPressCover(tester, 0);
      await _longPressCover(tester, 1);
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(calls, [1, 2]);
      // Both members gone → the group vanishes → empty state.
      expect(find.byType(MangaCoverGridTile), findsNothing);
      expect(find.text('No results found'), findsOneWidget);
      expect(find.text('Removed 2 from library'), findsOneWidget);
      // The read-once scan provider must not rebuild on a removal.
      expect(buildCount[0], 1);
    });

    testWidgets('a removal failure stops the loop and reports N of M', (
      tester,
    ) async {
      final calls = <int>[];
      await _pump(
        tester,
        library: [_m(1, 'A'), _m(2, 'A'), _m(3, 'A')],
        groups: const [
          (header: 'A', memberIds: [1, 2, 3], reasons: {DupReason.title}),
        ],
        remover: (ref, id) async {
          calls.add(id);
          if (id == 2) throw Exception('boom');
        },
      );

      await _longPressCover(tester, 0);
      await _longPressCover(tester, 1);
      await _longPressCover(tester, 2);
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Stopped at the first failure (id 2), never reached id 3.
      expect(calls, [1, 2]);
      expect(
        find.text("Removed 1 of 3. The rest couldn't be removed."),
        findsOneWidget,
      );
      // Only id 1 left in memory; the group still has 2 members and shows.
      expect(find.byType(MangaCoverGridTile), findsNWidgets(2));
    });

    testWidgets('remove is disabled with the offline tooltip while offline', (
      tester,
    ) async {
      await _pump(
        tester,
        library: [_m(1, 'A'), _m(2, 'A')],
        groups: const [
          (header: 'A', memberIds: [1, 2], reasons: {DupReason.title}),
        ],
        remover: (ref, id) async {},
        offline: true,
      );

      await _longPressCover(tester, 0);
      final remove = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
      );
      expect(remove.onPressed, isNull);
      expect(remove.tooltip, 'Reconnect to your server to remove entries');
    });
  });
}
