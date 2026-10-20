// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/library/data/badge_preference_migration.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/manga_cover/providers/manga_cover_providers.dart';
import 'package:tsumiru/src/widgets/manga_cover/widgets/manga_badges.dart';

const _kMangaId = 7;

Fragment$MangaDto _manga({
  int unread = 4,
  int downloads = 3,
  String lang = 'ja',
}) => Fragment$MangaDto(
  id: _kMangaId,
  title: 'Test Manga',
  bookmarkCount: 0,
  chapters: Fragment$MangaDto$chapters(totalCount: 10),
  downloadCount: downloads,
  genre: const [],
  inLibrary: true,
  inLibraryAt: '0',
  initialized: true,
  meta: const [],
  source: Fragment$MangaDto$source(
    id: '1',
    name: 'Test Source',
    displayName: 'Test Source',
    lang: lang,
    iconUrl: '/icon.png',
    contentWarning: Enum$ContentWarning.SAFE,
    $extension: Fragment$MangaDto$source$extension(isObsolete: false),
  ),
  sourceId: '1',
  status: Enum$MangaStatus.ONGOING,
  categories: Fragment$MangaDto$categories(nodes: const []),
  trackRecords: Fragment$MangaDto$trackRecords(nodes: const []),
  unreadCount: unread,
  updateStrategy: Enum$UpdateStrategy.ALWAYS_UPDATE,
  url: '/manga/7',
);

Future<void> _pumpBadges(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  Fragment$MangaDto? manga,
  bool onDevice = true,
  TextDirection textDirection = TextDirection.ltr,
  bool migrate = false,
  bool showCountBadges = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'onDeviceBadge': true,
    'downloadedBadge': true,
    'languageBadge': true,
    'sourceBadge': false,
    'localBadge': false,
    ...prefs,
  });
  final sp = await SharedPreferences.getInstance();
  // Stand in for the boot-time upgrade path, so a test can seed the pre-revamp
  // keys and assert on what the user ends up seeing.
  if (migrate) await migrateBadgePreferences(sp);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        offlineDeviceMangaIdsProvider.overrideWith(
          (ref) => Stream.value(onDevice ? {_kMangaId} : <int>{}),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 160,
                child: MangaBadgesRow(
                  manga: manga ?? _manga(),
                  showCountBadges: showCountBadges,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('unread badge modes', (tester) async {
    // Count shows the number.
    await _pumpBadges(tester);
    expect(find.text('4'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Dot shows no number but still draws a badge.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(
      tester,
      prefs: {'unreadBadgeMode': UnreadBadgeMode.dot.index},
    );
    expect(find.text('4'), findsNothing);
    expect(find.text('3'), findsOneWidget);

    // Hidden drops the unread badge entirely.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(
      tester,
      prefs: {'unreadBadgeMode': UnreadBadgeMode.hidden.index},
    );
    expect(find.text('4'), findsNothing);
    expect(find.text('3'), findsOneWidget);

    // The retired unreadBadge bool is no longer consulted.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(tester, prefs: {'unreadBadge': false});
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('on-device badge visibility', (tester) async {
    await _pumpBadges(tester);
    expect(find.byIcon(Icons.offline_pin_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(tester, onDevice: false);
    expect(find.byIcon(Icons.offline_pin_rounded), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(tester, prefs: {'onDeviceBadge': false});
    expect(find.byIcon(Icons.offline_pin_rounded), findsNothing);
  });

  testWidgets('language and source badges', (tester) async {
    // A mapped source language renders its flag.
    await _pumpBadges(tester);
    expect(find.text('🇯🇵'), findsOneWidget);

    // An unmapped language falls back to the uppercase code.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(tester, manga: _manga(lang: 'xx'));
    expect(find.text('XX'), findsOneWidget);

    // The source badge draws a folder for the local source (no extension).
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(
      tester,
      prefs: {'sourceBadge': true},
      manga: _manga(lang: 'localsourcelang'),
    );
    expect(find.byIcon(Icons.folder_rounded), findsOneWidget);

    // Otherwise it draws the extension icon.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(tester, prefs: {'sourceBadge': true});
    expect(find.byIcon(Icons.folder_rounded), findsNothing);

    // No source badge means no folder for the local source either.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(
      tester,
      prefs: {'sourceBadge': false},
      manga: _manga(lang: 'localsourcelang'),
    );
    expect(find.byIcon(Icons.folder_rounded), findsNothing);

    // The local source gets no language badge.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(
      tester,
      prefs: {'languageBadge': true},
      manga: _manga(lang: 'localsourcelang'),
    );
    expect(find.text('LOCALSOURCELANG'), findsNothing);
  });

  testWidgets('RTL and badge side swaps', (tester) async {
    // Everything on the LEFT still draws all four segments.
    await _pumpBadges(tester, prefs: {'badgeRightSide': <String>[]});
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.offline_pin_rounded), findsOneWidget);
    expect(find.text('🇯🇵'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // An RTL locale still reaches both physical corners.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(tester, textDirection: TextDirection.rtl);
    final row = tester.getRect(find.byType(MangaBadgesRow));
    expect(tester.getTopLeft(find.text('4')).dx, lessThan(row.center.dx));
    expect(
      tester.getTopRight(find.text('🇯🇵')).dx,
      greaterThan(row.center.dx),
    );

    // The Browse in-library marker stays left in RTL.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpBadges(
      tester,
      showCountBadges: false,
      textDirection: TextDirection.rtl,
    );
    final browseRow = tester.getRect(find.byType(MangaBadgesRow));
    final marker = find.byIcon(Icons.collections_bookmark_rounded);
    expect(tester.getCenter(marker).dx, lessThan(browseRow.center.dx));
  });

  testWidgets('layout migration', (tester) async {
    // An upgrade keeps the badges the user had set: pre-revamp keys in, the
    // same cover out.
    await _pumpBadges(
      tester,
      prefs: {'unreadBadge': false, 'localBadge': true, 'sourceBadge': false},
      migrate: true,
      manga: _manga(lang: 'localsourcelang'),
    );
    expect(find.text('4'), findsNothing, reason: 'unread badge stayed off');
    expect(
      find.byIcon(Icons.folder_rounded),
      findsOneWidget,
      reason: 'the Local Source badge survived as the source badge',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));

    // Unknown ids are dropped and new badges are appended.
    SharedPreferences.setMockInitialValues({
      'badgeOrder': <String>['source', 'not-a-badge', 'unread'],
      'badgeRightSide': <String>['unread'],
    });
    var sp = await SharedPreferences.getInstance();
    var container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    );
    var layout = container.read(libraryBadgeLayoutProvider);
    await tester.pump();
    expect(layout.length, LibraryBadge.values.length);
    expect(layout[0].badge, LibraryBadge.source);
    expect(layout[1].badge, LibraryBadge.unread);
    expect(layout.skip(2).map((p) => p.badge).toList(), [
      LibraryBadge.downloaded,
      LibraryBadge.onDevice,
      LibraryBadge.language,
    ]);
    expect(layout[1].side, BadgeSide.right);
    expect(layout[0].side, BadgeSide.left);
    container.dispose();
    await tester.pump();

    // The shipped default reproduces the previous fixed arrangement.
    SharedPreferences.setMockInitialValues(const {});
    sp = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    );
    layout = container.read(libraryBadgeLayoutProvider);
    await tester.pump();
    final left = layout
        .where((p) => p.side == BadgeSide.left)
        .map((p) => p.badge)
        .toList();
    final right = layout
        .where((p) => p.side == BadgeSide.right)
        .map((p) => p.badge)
        .toList();
    expect(left, [LibraryBadge.unread, LibraryBadge.downloaded]);
    expect(right, [
      LibraryBadge.onDevice,
      LibraryBadge.language,
      LibraryBadge.source,
    ]);
    container.dispose();
    await tester.pump();
  });

  testWidgets('nothing enabled renders nothing at all', (tester) async {
    await _pumpBadges(
      tester,
      prefs: {
        'unreadBadgeMode': UnreadBadgeMode.hidden.index,
        'downloadedBadge': false,
        'onDeviceBadge': false,
        'languageBadge': false,
      },
    );
    // No phantom padding either.
    expect(tester.getSize(find.byType(MangaBadgesRow)), const Size(160, 0));
  });
}
