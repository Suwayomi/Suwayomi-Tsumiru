// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
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

import '../manga_book/reader/reader_test_fixtures.dart';

MangaDto _m(int id, String title, {String? description}) =>
    testManga().copyWith.call(id: id, title: title, description: description);

class _FixedUnreachable extends ServerUnreachable {
  @override
  bool build() => true;
}

/// Stubs the scan result directly. `flutter test`'s widget-test binding
/// never resolves a record-typed `compute()` message — confirmed a harness
/// quirk, not a production bug, since the controller tests below exercise
/// the real `compute()` path via `ProviderContainer` and it resolves fine.
class _FakeLibraryDuplicates extends LibraryDuplicates {
  _FakeLibraryDuplicates(this._groups);
  final List<DupGroup> _groups;
  @override
  Future<List<DupGroup>> build({required bool checkDescriptions}) async =>
      _groups;
}

Override _fakeScan(bool checkDescriptions, List<DupGroup> groups) =>
    libraryDuplicatesProvider(
      checkDescriptions: checkDescriptions,
    ).overrideWith(() => _FakeLibraryDuplicates(groups));

Future<void> _pump(
  WidgetTester tester, {
  required List<MangaDto> library,
  List<Override> extra = const [],
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
        if (offline)
          serverUnreachableProvider.overrideWith(_FixedUnreachable.new),
        ...extra,
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

void main() {
  group('rendering (stubbed scan result)', () {
    testWidgets('an empty result shows the no-results state', (tester) async {
      await _pump(
        tester,
        library: const [],
        extra: [_fakeScan(false, const [])],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('No results found'), findsOneWidget);
    });

    testWidgets('a group renders its members\' covers and header', (
      tester,
    ) async {
      final members = [_m(1, 'Solo Leveling'), _m(2, 'Solo Leveling')];
      const group = (
        header: 'Solo Leveling',
        memberIds: [1, 2],
        reasons: {DupReason.title},
      );
      await _pump(
        tester,
        library: members,
        extra: [
          _fakeScan(false, const [group]),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Solo Leveling'), findsWidgets);
    });

    testWidgets('a tracker-reason group shows the certain-match chip', (
      tester,
    ) async {
      final members = [_m(1, 'A'), _m(2, 'B')];
      const group = (
        header: 'A',
        memberIds: [1, 2],
        reasons: {DupReason.tracker},
      );
      await _pump(
        tester,
        library: members,
        extra: [
          _fakeScan(false, const [group]),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Same tracker entry'), findsOneWidget);
    });
  });

  group('toggle', () {
    testWidgets(
      'flips which family instance the screen reads — different results '
      'for checkDescriptions true vs false',
      (tester) async {
        const withoutDescription = <DupGroup>[];
        const withDescription = <DupGroup>[
          (
            header: 'Rare Title Example',
            memberIds: [1, 2],
            reasons: {DupReason.description},
          ),
        ];
        await _pump(
          tester,
          library: [
            _m(1, 'Rare Title Example'),
            _m(2, 'Something Else', description: 'mentions it'),
          ],
          extra: [
            _fakeScan(false, withoutDescription),
            _fakeScan(true, withDescription),
          ],
        );

        expect(find.text('No results found'), findsOneWidget);
        expect(find.text('Rare Title Example'), findsNothing);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        expect(find.text('No results found'), findsNothing);
        // Both the group header and the member's own cover title render it.
        expect(find.text('Rare Title Example'), findsWidgets);
      },
    );

    testWidgets('offline forces the toggle off and disabled', (tester) async {
      await _pump(
        tester,
        library: const [],
        offline: true,
        extra: [
          // Persisted pref is ON — proves the offline UI overrides it rather
          // than just reflecting an already-off value.
          libraryDuplicatesCheckDescriptionProvider.overrideWithValue(true),
          _fakeScan(false, const []),
        ],
      );

      expect(tester.takeException(), isNull);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isFalse);
      expect(toggle.onChanged, isNull);
      expect(find.text('Offline: matching by title only'), findsOneWidget);
    });
  });
}
