// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/widgets/update_status_summary_sheet.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

MangaDto _manga(int id) => Fragment$MangaDto(
      id: id,
      title: 'M$id',
      bookmarkCount: 0,
      chapters: Fragment$MangaDto$chapters(totalCount: 0),
      downloadCount: 0,
      genre: const [],
      inLibrary: true,
      inLibraryAt: '0',
      initialized: true,
      meta: const [],
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
      unreadCount: 0,
      updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
      url: '/manga/$id',
    );

Future<Widget> _harness({
  required void Function(MangaDto)? onMigrate,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineDeviceMangaIdsProvider.overrideWith((ref) async => <int>{}),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ListView(
          children: [
            UpdateStatusExpansionTile(
              mangas: [_manga(7)],
              title: 'Failed',
              initiallyExpanded: true,
              onMigrate: onMigrate,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping Migrate runs migration for that exact series',
      (tester) async {
    MangaDto? migrated;
    await tester.pumpWidget(await _harness(onMigrate: (m) => migrated = m));
    await tester.pump();

    expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
    await tester.pump();

    expect(migrated?.id, 7); // the row's own series, not some other
  });

  testWidgets('no Migrate button when migration is not offered',
      (tester) async {
    await tester.pumpWidget(await _harness(onMigrate: null));
    await tester.pump();
    expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing);
  });
}
