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
import 'package:tsumiru/src/features/browse_center/domain/source/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/library/data/badge_preference_migration.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/offline/data/offline_download_providers.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/manga_cover/providers/manga_cover_providers.dart';
import 'package:tsumiru/src/widgets/manga_cover/widgets/manga_badges.dart';
import 'package:tsumiru/src/widgets/server_image.dart';

const _kMangaId = 7;

Fragment$MangaDto _manga({
  int unread = 4,
  int downloads = 3,
  String lang = 'ja',
}) =>
    Fragment$MangaDto(
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
      source: Fragment$SourceDto(
        id: '1',
        name: 'Test Source',
        displayName: 'Test Source',
        lang: lang,
        iconUrl: '/icon.png',
        contentWarning: Enum$ContentWarning.SAFE,
        isConfigurable: false,
        supportsLatest: true,
        meta: const [],
        $extension: Fragment$SourceDto$extension(
          pkgName: 'test',
          isObsolete: false,
        ),
      ),
      sourceId: '1',
      status: Enum$MangaStatus.ONGOING,
      categories: Fragment$MangaDto$categories(nodes: const []),
      trackRecords:
          Fragment$MangaDto$trackRecords(totalCount: 0, nodes: const []),
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
  await tester.pumpWidget(ProviderScope(
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
  ));
  await tester.pump();
}

void main() {
  group('unread badge modes', () {
    testWidgets('count shows the number', (tester) async {
      await _pumpBadges(tester);
      expect(find.text('4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dot shows no number but still draws a badge', (tester) async {
      await _pumpBadges(
        tester,
        prefs: {'unreadBadgeMode': UnreadBadgeMode.dot.index},
      );
      expect(find.text('4'), findsNothing);
      // The download count is unaffected, so the strip is still there.
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('hidden drops the unread badge entirely', (tester) async {
      await _pumpBadges(
        tester,
        prefs: {'unreadBadgeMode': UnreadBadgeMode.hidden.index},
      );
      expect(find.text('4'), findsNothing);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('the retired unreadBadge bool is no longer consulted',
        (tester) async {
      // unreadBadgeMode is the single source of truth.
      await _pumpBadges(tester, prefs: {'unreadBadge': false});
      expect(find.text('4'), findsOneWidget);
    });
  });

  group('badge sides', () {
    testWidgets('on-device renders when the manga has device downloads',
        (tester) async {
      await _pumpBadges(tester);
      expect(find.byIcon(Icons.offline_pin_rounded), findsOneWidget);
    });

    testWidgets('on-device is absent when nothing is downloaded here',
        (tester) async {
      await _pumpBadges(tester, onDevice: false);
      expect(find.byIcon(Icons.offline_pin_rounded), findsNothing);
    });

    testWidgets('on-device is absent when the setting is off, even if downloaded',
        (tester) async {
      await _pumpBadges(tester, prefs: {'onDeviceBadge': false});
      expect(find.byIcon(Icons.offline_pin_rounded), findsNothing);
    });

    testWidgets('the language flag renders for a mapped source language',
        (tester) async {
      await _pumpBadges(tester);
      expect(find.text('🇯🇵'), findsOneWidget);
    });

    testWidgets('an unmapped language falls back to the uppercase code',
        (tester) async {
      await _pumpBadges(tester, manga: _manga(lang: 'xx'));
      expect(find.text('XX'), findsOneWidget);
    });

    testWidgets('the source badge draws a folder for the local source',
        (tester) async {
      // Local Source is just a source with no extension icon to fetch, so the
      // one source badge covers it — this is what `localBadge` used to draw.
      await _pumpBadges(
        tester,
        prefs: {'sourceBadge': true},
        manga: _manga(lang: 'localsourcelang'),
      );
      expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
    });

    testWidgets('the source badge draws the extension icon otherwise',
        (tester) async {
      await _pumpBadges(tester, prefs: {'sourceBadge': true});
      expect(find.byIcon(Icons.folder_rounded), findsNothing);
    });

    testWidgets('no source badge means no folder for the local source either',
        (tester) async {
      await _pumpBadges(
        tester,
        prefs: {'sourceBadge': false},
        manga: _manga(lang: 'localsourcelang'),
      );
      expect(find.byIcon(Icons.folder_rounded), findsNothing);
    });

    testWidgets('the local source gets no language badge', (tester) async {
      await _pumpBadges(
        tester,
        prefs: {'languageBadge': true},
        manga: _manga(lang: 'localsourcelang'),
      );
      expect(find.text('LOCALSOURCELANG'), findsNothing);
    });

    testWidgets('moving a badge to the other side keeps it rendered',
        (tester) async {
      // Everything on the LEFT: the strip still draws all four segments.
      await _pumpBadges(tester, prefs: {'badgeRightSide': <String>[]});
      expect(find.text('4'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.offline_pin_rounded), findsOneWidget);
      expect(find.text('🇯🇵'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an RTL locale still reaches both physical corners',
        (tester) async {
      await _pumpBadges(tester, textDirection: TextDirection.rtl);
      final row = tester.getRect(find.byType(MangaBadgesRow));
      // Each cluster hugs its own corner, inside the row's 8px padding.
      expect(tester.getTopLeft(find.text('4')).dx, lessThan(row.center.dx));
      expect(
        tester.getTopRight(find.text('🇯🇵')).dx,
        greaterThan(row.center.dx),
      );
    });

    testWidgets('the Browse in-library marker stays left in an RTL locale',
        (tester) async {
      // Browse and global-search covers take their own path through the row.
      await _pumpBadges(
        tester,
        showCountBadges: false,
        textDirection: TextDirection.rtl,
      );
      final row = tester.getRect(find.byType(MangaBadgesRow));
      final marker = find.byIcon(Icons.collections_bookmark_rounded);
      expect(tester.getCenter(marker).dx, lessThan(row.center.dx));
    });

    testWidgets('an upgrade keeps the badges the user had set', (tester) async {
      // The point of the migration: what it writes is what the renderer reads.
      // Pre-revamp keys in, the same cover out.
      await _pumpBadges(
        tester,
        prefs: {
          'unreadBadge': false,
          'localBadge': true,
          'sourceBadge': false,
        },
        migrate: true,
        manga: _manga(lang: 'localsourcelang'),
      );

      expect(find.text('4'), findsNothing, reason: 'unread badge stayed off');
      expect(find.byIcon(Icons.folder_rounded), findsOneWidget,
          reason: 'the Local Source badge survived as the source badge');
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
      expect(
        tester.getSize(find.byType(MangaBadgesRow)),
        const Size(160, 0),
      );
    });

    testWidgets('survives an unbounded width (the list tiles give none)',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'onDeviceBadge': true,
        'downloadedBadge': true,
        'languageBadge': true,
      });
      final sp = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          offlineDeviceMangaIdsProvider.overrideWith((ref) => Stream.value({_kMangaId})),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            // A Row lays non-flex children out with unbounded width — exactly
            // what MangaCoverListTile does.
            body: Row(
              children: [
                MangaBadgesRow(manga: _manga(), showCountBadges: true),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('🇯🇵'), findsOneWidget);
    });

    testWidgets('the unbounded path keeps its cluster order in RTL',
        (tester) async {
      // The list tiles take the min-width branch, which orders the two clusters
      // itself rather than pinning them to corners — RTL would swap them.
      SharedPreferences.setMockInitialValues({
        'onDeviceBadge': true,
        'downloadedBadge': true,
        'languageBadge': true,
      });
      final sp = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          offlineDeviceMangaIdsProvider.overrideWith((ref) => Stream.value({_kMangaId})),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Row(
                children: [
                  MangaBadgesRow(manga: _manga(), showCountBadges: true),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(
        tester.getCenter(find.text('4')).dx,
        lessThan(tester.getCenter(find.text('🇯🇵')).dx),
      );
    });
  });

  group('badge height', () {
    // 20dp strip (MangaBadgesRow._stripHeight at text scale 1.0) inside the row's
    // 8dp padding. Every combination must land on exactly this — a lone badge
    // used to size to its own content instead (12dp for a count, 16dp for an
    // icon) and visibly shrank the moment a second badge joined its corner.
    const expected = 20.0 + 8 * 2;

    // One pump per test: re-pumping into a fresh prefs instance re-runs the
    // preference notifiers' late-final init and throws.
    final cases = <String, Map<String, Object>>{
      'a lone text badge': {
        'downloadedBadge': false,
        'onDeviceBadge': false,
        'languageBadge': false,
      },
      'a lone icon badge': {
        'unreadBadgeMode': UnreadBadgeMode.hidden.index,
        'downloadedBadge': false,
        'onDeviceBadge': true,
        'languageBadge': false,
      },
      'two badges sharing one corner': {
        'downloadedBadge': true,
        'onDeviceBadge': false,
        'languageBadge': false,
        'badgeRightSide': <String>[],
      },
    };

    cases.forEach((name, prefs) {
      testWidgets('$name is $expected tall', (tester) async {
        await _pumpBadges(tester, prefs: prefs);
        expect(tester.getSize(find.byType(MangaBadgesRow)).height, expected);
      });
    });
  });

  group('badge alignment', () {
    // The strip at text scale 1.0, and the cell an icon segment gets (80%).
    const strip = 20.0;
    const cell = strip * .8;

    testWidgets('the flag segment fills the strip, so it cannot sit off centre',
        (tester) async {
      await _pumpBadges(tester, prefs: {
        'unreadBadgeMode': UnreadBadgeMode.hidden.index,
        'downloadedBadge': false,
        'onDeviceBadge': false,
        'languageBadge': true,
      });

      // The regression this pins: `height: 1` pinned the line box to ONE EM
      // (14dp in a 20dp strip) and left Center() to place it. Because a font's
      // ascent:descent split is lopsided, squeezing the box to 1em put the
      // glyph ~1dp above the strip's centre line. A line box of exactly one
      // strip leaves no room to be off-centre — and still bounds the emoji's
      // line spacing, which is what `height: 1` was there for.
      // Font-independent: fontSize x (1 / ratio) == strip for any font.
      final text = tester.getRect(find.text('🇯🇵'));
      expect(text.height, closeTo(strip, 0.01));
      expect(
        text.center.dy,
        closeTo(tester.getRect(find.byType(ClipRRect).first).center.dy, 0.01),
      );
    });

    testWidgets('every badge segment centres its text', (tester) async {
      await _pumpBadges(tester, manga: _manga(lang: 'xx'));
      final texts = tester.widgetList<Text>(find.byType(Text));
      expect(texts, isNotEmpty);
      for (final text in texts) {
        expect(text.textAlign, TextAlign.center, reason: 'segment "${text.data}"');
      }
    });

    testWidgets('the source icon and its stand-in stay inside the badge cell',
        (tester) async {
      await _pumpBadges(tester, prefs: {
        'unreadBadgeMode': UnreadBadgeMode.hidden.index,
        'downloadedBadge': false,
        'onDeviceBadge': false,
        'languageBadge': false,
        'sourceBadge': true,
      });
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ServerImage)), const Size(cell, cell));

      // ServerImage's stock stand-ins are sized for a full-page image: the
      // placeholder is a screen-relative shimmer (35% of the window) around a
      // 24dp ImageIcon, and the failure glyph a bare 24dp broken_image. Both
      // overflowed a 16dp cell. The placeholder is now cell-sized outright...
      final placeholder = tester.getSize(find.byIcon(Icons.extension_rounded));
      expect(placeholder.width, lessThanOrEqualTo(cell));
      expect(placeholder.height, lessThanOrEqualTo(cell));
      // ...and an IconTheme caps whatever unsized icon it falls back to.
      expect(
        IconTheme.of(tester.element(find.byType(ServerImage))).size,
        cell,
      );
    });
  });

  group('badge layout preference', () {
    test('unknown ids are dropped and new badges are appended', () async {
      SharedPreferences.setMockInitialValues({
        // A stale id plus a partial order.
        'badgeOrder': <String>['source', 'not-a-badge', 'unread'],
        'badgeRightSide': <String>['unread'],
      });
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);

      final layout = container.read(libraryBadgeLayoutProvider);
      expect(layout.length, LibraryBadge.values.length);
      // Saved order first, unknown id skipped.
      expect(layout[0].badge, LibraryBadge.source);
      expect(layout[1].badge, LibraryBadge.unread);
      // Never-mentioned badges follow in declaration order.
      expect(
        layout.skip(2).map((p) => p.badge).toList(),
        [
          LibraryBadge.downloaded,
          LibraryBadge.onDevice,
          LibraryBadge.language,
        ],
      );
      // Side comes from badgeRightSide, not from the order.
      expect(layout[1].side, BadgeSide.right);
      expect(layout[0].side, BadgeSide.left);
    });

    test('the shipped default reproduces the previous fixed arrangement',
        () async {
      SharedPreferences.setMockInitialValues(const {});
      final sp = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);

      final layout = container.read(libraryBadgeLayoutProvider);
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
    });
  });
}
