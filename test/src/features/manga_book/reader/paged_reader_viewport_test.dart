// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_display_window.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_reader_viewport.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_spread_mapping.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_wrapper.dart';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

List<String> _localPages(int count) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-paged-reader-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

ReaderInputCallbacks _callbacks() => ReaderInputCallbacks(
  onTap: () {},
  onLongPressStart: (_) {},
  onLongPressMoveUpdate: (_) {},
  onLongPressEnd: () {},
  onLongPressCancel: () {},
  onNext: () {},
  onPrevious: () {},
  onNextBoundary: () => false,
  onPreviousBoundary: () => false,
  navigationLayout: ReaderNavigationLayout.disabled,
  tapInvert: TapInvert.none,
  smallerTapZones: false,
);

Future<void> _pumpViewport(
  WidgetTester tester, {
  required PagedReaderController controller,
  required SpreadMapping mapping,
  required List<String> pages,
  required int initialDisplayIndex,
  required ValueChanged<int> onRawPageChanged,
  required ReaderInputCallbacks callbacks,
}) async {
  final window = buildPagedDisplayWindow(
    chapters: [
      WindowChapter(
        chapterId: 1,
        chapterName: 'c1',
        mapping: mapping,
        pages: pages,
      ),
    ],
    forceTransition: false,
  );
  final viewport = ReaderInputScope(
    callbacks: callbacks,
    child: SizedBox(
      width: 300,
      height: 500,
      child: PagedReaderViewport(
        controller: controller,
        window: window,
        initialDisplayIndex: initialDisplayIndex,
        axis: Axis.horizontal,
        reverse: false,
        animateTransitions: false,
        pageFit: BoxFit.contain,
        pageSize: null,
        pagesAtNaturalSize: false,
        mouseScrollSpeed: 1.7,
        centerMargin: CenterMarginType.none,
        rotateWide: false,
        rotateWideInvert: false,
        reversePair: false,
        cropBorders: false,
        onPageWide: (_, _, _) {},
        onChapterPageChanged: (_, raw) => onRawPageChanged(raw),
        transitionBuilder: (_) => const SizedBox.shrink(),
        pinchEnabled: true,
        doubleTapToZoom: true,
        disableZoomIn: false,
        disableZoomOut: false,
        navigateToPan: true,
      ),
    ),
  );
  await tester.pumpWidget(
    Directionality(textDirection: TextDirection.ltr, child: viewport),
  );
  await tester.pump();
}

void main() {
  Future<List<double>> strandAndSettle(
    WidgetTester tester,
    PagedReaderController controller,
    double progress,
  ) async {
    controller.debugStrand(progress);
    await tester.pumpAndSettle();
    return [
      for (final transform in tester.widgetList<Transform>(
        find.ancestor(
          of: find.byType(ClipRect),
          matching: find.byType(Transform),
        ),
      ))
        transform.transform.storage[12],
    ];
  }

  testWidgets('a barely-started turn snaps back instead of skipping a page', (
    tester,
  ) async {
    // 0.19 clears the 0.18 turn threshold, so recovering through the normal
    // settle logic would advance the page.
    final pages = _localPages(3);
    final mapping = buildSpreadMapping(
      pageCount: pages.length,
      doublePages: false,
      splitWide: false,
      splitInvert: false,
      isWide: (_) => false,
    );
    final controller = PagedReaderController();
    final seen = <int>[];
    await _pumpViewport(
      tester,
      controller: controller,
      mapping: mapping,
      pages: pages,
      initialDisplayIndex: 0,
      onRawPageChanged: seen.add,
      callbacks: _callbacks(),
    );
    seen.clear();

    await strandAndSettle(tester, controller, 0.19);

    expect(seen, isEmpty, reason: 'recovery moved the reader off the page');
  });
}
