// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tsumiru/src/constants/enum.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/double_page_view.dart';
import 'package:tsumiru/src/features/manga_book/presentation/reader/widgets/reader_mode/paged_spread_mapping.dart';

const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

List<String> _localPages(int count) {
  final dir = Directory.systemTemp.createTempSync('tsumiru-double-page-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final bytes = base64Decode(_png1x1);
  return [
    for (var i = 0; i < count; i++)
      (File('${dir.path}/$i.png')..writeAsBytesSync(bytes)).uri.toString(),
  ];
}

Future<void> _pumpDoublePage(
  WidgetTester tester, {
  required SpreadEntry entry,
  required List<String> pages,
  bool reversePair = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 600,
          child: DoublePageView(
            entry: entry,
            pages: pages,
            pageFit: BoxFit.contain,
            pageSize: null,
            centerMargin: CenterMarginType.none,
            rotateWide: false,
            rotateWideInvert: false,
            reversePair: reversePair,
            onPageWide: (_, __) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('paired pages align toward the center spine', (tester) async {
    await _pumpDoublePage(
      tester,
      entry: const SpreadEntry(PageUnit(0), PageUnit(1)),
      pages: _localPages(2),
    );

    final images = tester.widgetList<Image>(find.byType(Image)).toList();

    expect(images, hasLength(2));
    expect(images[0].alignment, Alignment.centerRight);
    expect(images[1].alignment, Alignment.centerLeft);
  });

  testWidgets('single pages keep centered alignment', (tester) async {
    await _pumpDoublePage(
      tester,
      entry: const SpreadEntry(PageUnit(0)),
      pages: _localPages(1),
    );

    final image = tester.widget<Image>(find.byType(Image));

    expect(image.alignment, Alignment.center);
  });
}
