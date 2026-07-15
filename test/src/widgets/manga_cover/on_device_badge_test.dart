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
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/widgets/manga_cover/widgets/manga_badges.dart';

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

Future<Widget> _harness(Set<int> deviceIds, MangaDto manga) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      offlineDeviceMangaIdsProvider.overrideWith((ref) async => deviceIds),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: MangaBadgesRow(manga: manga, showCountBadges: true),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the on-device pin when the series is downloaded here',
      (tester) async {
    await tester.pumpWidget(await _harness({5}, _manga(5)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.offline_pin_rounded), findsOneWidget);
  });

  testWidgets('no badge when the series has nothing on this device',
      (tester) async {
    await tester.pumpWidget(await _harness({7}, _manga(5)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.offline_pin_rounded), findsNothing);
  });
}
