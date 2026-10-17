// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';
import 'package:tsumiru/src/widgets/cover_row_section.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required int itemCount,
  VoidCallback? onSeeAll,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CoverRowSection(
          title: 'Row',
          onSeeAll: onSeeAll,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          height: 120,
          itemCount: itemCount,
          itemBuilder: (context, index) =>
              SizedBox(width: 100, height: 120, child: Text('Item $index')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('overflowing row shows paging arrows and the edge fade', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1000, 600), itemCount: 20);

    expect(find.byType(IconButton), findsNWidgets(2));
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);

    final arrows = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .toList();
    expect(arrows.first.onPressed, isNull);
    expect(arrows.last.onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.controller!.offset, greaterThan(0));
  });

  testWidgets('a row that fits shows no arrows and no fade', (tester) async {
    await _pump(tester, size: const Size(1000, 600), itemCount: 3);

    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('phone header is a tappable title with no paging arrows', (
    tester,
  ) async {
    var seeAllCalls = 0;
    await _pump(
      tester,
      size: const Size(412, 900),
      itemCount: 20,
      onSeeAll: () => seeAllCalls++,
    );

    expect(find.text('See all'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);

    await tester.tap(find.text('Row'));
    expect(seeAllCalls, 1);
  });

  testWidgets('See all calls onSeeAll on a wide layout', (tester) async {
    var seeAllCalls = 0;
    await _pump(
      tester,
      size: const Size(1000, 600),
      itemCount: 20,
      onSeeAll: () => seeAllCalls++,
    );

    await tester.tap(find.text('See all'));
    expect(seeAllCalls, 1);
  });
}
