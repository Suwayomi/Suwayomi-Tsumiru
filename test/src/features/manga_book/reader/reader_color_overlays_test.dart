// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Custom-filter overlay contract (design §2.4 layer 3): the color math
// (brightness alpha, grayscale/invert matrices), the leaf-overlay behavior
// (draft ?? committed, inert-positive brightness), the chrome z-order
// (filters < flash < bars), and the zero-viewer-rebuild preview discipline.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/chapter_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/chapter_page/chapter_page_model.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/graphql/__generated__/fragment.graphql.dart';
import 'package:tsumiru/src/features/manga_book/domain/manga/manga_model.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_controller.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/controller/reader_preview_channel.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_bottom_controls.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_chrome.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_color_overlays.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_flash_overlay.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/chrome/reader_top_bar.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/graphql/__generated__/schema.graphql.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

/// Applies a 4x5 color matrix to an RGBA pixel (0..255 scale), like Skia.
List<double> _apply(List<double> m, List<double> p) => [
      for (var r = 0; r < 4; r++)
        m[r * 5] * p[0] +
            m[r * 5 + 1] * p[1] +
            m[r * 5 + 2] * p[2] +
            m[r * 5 + 3] * p[3] +
            m[r * 5 + 4],
    ];

MangaDto _manga() => Fragment$MangaDto(
      id: 1,
      title: 'Test Manga',
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
      url: '/manga/1',
    );

ChapterDto _chapter() => Fragment$ChapterDto(
      chapterNumber: 1,
      fetchedAt: '0',
      id: 1,
      isBookmarked: false,
      isDownloaded: false,
      isRead: false,
      lastPageRead: 0,
      lastReadAt: '0',
      mangaId: 1,
      name: 'Chapter 1',
      pageCount: 3,
      sourceOrder: 1,
      uploadDate: '0',
      url: '/chapter/1',
      meta: const [],
    );

/// Viewer stand-in that counts its own builds.
class _Probe extends StatefulWidget {
  const _Probe({required this.onBuild});

  final VoidCallback onBuild;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return const ColoredBox(color: Colors.white);
  }
}

void main() {
  setUp(() {
    readerBrightnessPreview.value = null;
    readerColorFilterPreview.value = null;
  });

  group('overlay math (Komikku parity)', () {
    test('brightness alpha = abs(value)/100 for negatives, clamped', () {
      expect(brightnessOverlayAlpha(-75), 0.75);
      expect(brightnessOverlayAlpha(-1), 0.01);
      expect(brightnessOverlayAlpha(-50), 0.5);
      expect(brightnessOverlayAlpha(-200), 1.0, reason: 'clamped');
    });

    test('brightness 0 and positives render no overlay (inert positive)', () {
      expect(brightnessOverlayAlpha(0), 0.0);
      expect(brightnessOverlayAlpha(50), 0.0);
      expect(brightnessOverlayAlpha(100), 0.0);
    });

    test('grayscale matrix = Android setSaturation(0) luminance weights', () {
      const white = <double>[255, 255, 255, 255];
      const red = <double>[255, 0, 0, 255];
      expect(_apply(kGrayscaleColorMatrix, white), [255, 255, 255, 255]);
      final gray = _apply(kGrayscaleColorMatrix, red);
      expect(gray[0], closeTo(0.213 * 255, 0.001));
      expect(gray[0], gray[1]);
      expect(gray[1], gray[2]);
      expect(gray[3], 255, reason: 'alpha untouched');
    });

    test('invert matrix = Komikku getCombinedPaint inversion', () {
      const white = <double>[255, 255, 255, 255];
      const black = <double>[0, 0, 0, 255];
      expect(_apply(kInvertColorMatrix, white), [0, 0, 0, 255]);
      expect(_apply(kInvertColorMatrix, black), [255, 255, 255, 255]);
    });

    test('combined = grayscale first, then invert (postConcat order)', () {
      final combined = grayscaleInvertMatrix(grayscale: true, inverted: true);
      const red = <double>[255, 0, 0, 255];
      final out = _apply(combined, red);
      // red → gray 54.315 → inverted 200.685; same on all three channels.
      expect(out[0], closeTo(255 - 0.213 * 255, 0.001));
      expect(out[0], out[1]);
      expect(out[1], out[2]);
      expect(out[3], 255);
    });

    test('single-toggle matrices pass through unchanged', () {
      expect(
        grayscaleInvertMatrix(grayscale: true, inverted: false),
        kGrayscaleColorMatrix,
      );
      expect(
        grayscaleInvertMatrix(grayscale: false, inverted: true),
        kInvertColorMatrix,
      );
    });
  });

  group('ReaderColorOverlays', () {
    Future<void> pumpOverlays(
      WidgetTester tester, {
      Map<String, Object> prefValues = const {},
      Widget? sibling,
    }) async {
      SharedPreferences.setMockInitialValues(prefValues);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Stack(
              fit: StackFit.expand,
              children: [
                if (sibling != null) sibling,
                const ReaderColorOverlays(),
              ],
            ),
          ),
        ),
      );
    }

    Finder inOverlays(Type type) => find.descendant(
          of: find.byType(ReaderColorOverlays),
          matching: find.byType(type),
        );

    Color? dimColor(WidgetTester tester) {
      final boxes = inOverlays(ColoredBox);
      if (boxes.evaluate().isEmpty) return null;
      return tester.widget<ColoredBox>(boxes.first).color;
    }

    testWidgets('everything off → renders nothing', (tester) async {
      await pumpOverlays(tester);
      expect(inOverlays(BackdropFilter), findsNothing);
      expect(inOverlays(ColoredBox), findsNothing);
    });

    testWidgets('committed -50 brightness → black dim at 0.5', (tester) async {
      await pumpOverlays(tester, prefValues: {
        'customBrightness': true,
        'customBrightnessValue': -50,
      });
      final color = dimColor(tester);
      expect(color, isNotNull);
      expect(color!.a, closeTo(0.5, 0.005));
    });

    testWidgets('positive committed brightness is inert (no overlay)',
        (tester) async {
      await pumpOverlays(tester, prefValues: {
        'customBrightness': true,
        'customBrightnessValue': 60,
      });
      expect(dimColor(tester), isNull);
    });

    testWidgets('brightness draft overrides committed; clearing falls back',
        (tester) async {
      await pumpOverlays(tester, prefValues: {
        'customBrightness': true,
        'customBrightnessValue': -20,
      });
      expect(dimColor(tester)!.a, closeTo(0.2, 0.005));

      readerBrightnessPreview.value = -75;
      await tester.pump();
      expect(dimColor(tester)!.a, closeTo(0.75, 0.005));

      readerBrightnessPreview.value = null;
      await tester.pump();
      expect(dimColor(tester)!.a, closeTo(0.2, 0.005));
    });

    testWidgets('grayscale/invert mount one matrix BackdropFilter',
        (tester) async {
      await pumpOverlays(tester, prefValues: {'grayscale': true});
      expect(inOverlays(BackdropFilter), findsOneWidget);
      expect(
        tester.widget<BackdropFilter>(inOverlays(BackdropFilter)).filter,
        ColorFilter.matrix(
          grayscaleInvertMatrix(grayscale: true, inverted: false),
        ),
      );
    });

    testWidgets('color filter blends draft ?? committed ARGB', (tester) async {
      const committed = 0x80FF0000; // half-alpha red
      await pumpOverlays(tester, prefValues: {
        'customColorFilter': true,
        'colorFilterValue': committed,
        'colorFilterBlendMode': ColorFilterBlendMode.multiply.index,
      });
      BackdropFilter filterWidget() =>
          tester.widget<BackdropFilter>(inOverlays(BackdropFilter));
      expect(
        filterWidget().filter,
        const ColorFilter.mode(Color(committed), BlendMode.modulate),
      );

      const draft = 0x8000FF00;
      readerColorFilterPreview.value = draft;
      await tester.pump();
      expect(
        filterWidget().filter,
        const ColorFilter.mode(Color(draft), BlendMode.modulate),
      );
    });

    testWidgets('preview drag repaints ONLY the overlay: zero probe rebuilds',
        (tester) async {
      var probeBuilds = 0;
      await pumpOverlays(
        tester,
        prefValues: {'customBrightness': true},
        sibling: _Probe(onBuild: () => probeBuilds++),
      );
      expect(probeBuilds, 1);

      for (var v = -10; v >= -70; v -= 10) {
        readerBrightnessPreview.value = v;
        await tester.pump();
      }
      expect(dimColor(tester)!.a, closeTo(0.7, 0.005));
      expect(probeBuilds, 1,
          reason: 'slider-drag preview must never rebuild the viewer');
    });
  });

  group('chrome z-order', () {
    testWidgets('filters < flash < top bar / bottom bar in the chrome Stack',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final visibility = ValueNotifier(true);
      addTearDown(visibility.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            chapterProvider(chapterId: 1).overrideWith((ref) => _chapter()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReaderChrome(
                manga: _manga(),
                chapter: _chapter(),
                chapterPages: ChapterPagesDto(
                  chapter: ChapterPagesChapterDto(id: 1, pageCount: 3),
                  pages: const ['a', 'b', 'c'],
                ),
                currentIndex: 0,
                totalPageCount: null,
                visibility: visibility,
                useBottomSeekBar: true,
                showSideSeekBar: false,
                scrollDirection: Axis.horizontal,
                nextPrevChapterPair: null,
                resolvedReaderMode: ReaderMode.singleHorizontalLTR,
                reverseSeekBar: false,
                onChanged: (_) {},
                onOpenSettings: () {},
                onOpenReaderMode: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final stackFinder = find
          .descendant(
              of: find.byType(ReaderChrome), matching: find.byType(Stack))
          .first;
      final stack = tester.widget<Stack>(stackFinder);
      final stackElement = tester.element(stackFinder);

      // The Stack child (by index) that a widget deep in a subtree belongs to.
      int childIndexOf(Type type) {
        Element? current = tester.element(find.byType(type));
        Widget? topLevel;
        while (current != null && current != stackElement) {
          topLevel = current.widget;
          Element? parent;
          current.visitAncestorElements((a) {
            parent = a;
            return false;
          });
          current = parent;
        }
        return stack.children.indexWhere((w) => identical(w, topLevel));
      }

      final filters = childIndexOf(ReaderColorOverlays);
      final flash = childIndexOf(ReaderFlashOverlay);
      final topBar = childIndexOf(ReaderTopBar);
      final bottomBar = childIndexOf(ReaderBottomControls);

      expect(filters, isNonNegative);
      expect(filters, lessThan(flash),
          reason: 'flash must stay visible over active filters');
      expect(flash, lessThan(topBar), reason: 'bars paint above the flash');
      expect(flash, lessThan(bottomBar));
      expect(filters, lessThan(topBar),
          reason: 'chrome bars must never get tinted by the filters');
      expect(filters, lessThan(bottomBar));
    });
  });
}
