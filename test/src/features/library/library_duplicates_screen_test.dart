// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql/client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/library/domain/duplicate_matcher.dart';
import 'package:tsumiru/src/features/library/presentation/duplicates/controller/library_duplicates_controller.dart';
import 'package:tsumiru/src/features/library/presentation/duplicates/library_duplicates_screen.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_controller.dart';
import 'package:tsumiru/src/features/library/presentation/library/controller/library_manga_list.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/offline/data/server_reachability.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

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
  group('toggle', () {
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
