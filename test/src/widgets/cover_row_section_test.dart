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
  testWidgets('an overflowing row shows arrows and fade, then ends at offset', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1000, 600), itemCount: 20);

    expect(find.byType(IconButton), findsNWidgets(2));
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(
      tester.widget<CoverRowEdgeFade>(find.byType(CoverRowEdgeFade)).fade,
      isTrue,
    );
    final arrows = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .toList();
    expect(arrows.first.onPressed, isNull);
    expect(arrows.last.onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();

    // Reaching the end keeps the offset and drops the fade.
    final position = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .position;
    expect(position.pixels, position.maxScrollExtent);
    expect(
      tester.widget<CoverRowEdgeFade>(find.byType(CoverRowEdgeFade)).fade,
      isFalse,
    );
  });

  testWidgets('a row that fits shows no arrows, titled or not', (tester) async {
    await _pump(tester, size: const Size(1000, 600), itemCount: 3);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(
      tester.widget<CoverRowEdgeFade>(find.byType(CoverRowEdgeFade)).fade,
      isFalse,
    );

    // A header-less row shows arrows only while it overflows.
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> pump(int itemCount) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CoverRowSection(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            height: 120,
            itemCount: itemCount,
            itemBuilder: (context, index) =>
                SizedBox(width: 100, height: 120, child: Text('Item $index')),
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(3);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byTooltip('Next'), findsNothing);
    await pump(20);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Next'), findsOneWidget);
  });

  testWidgets('phone header and See all', (tester) async {
    // On a phone the header is a tappable title with no paging arrows.
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

    // On a wide layout See all calls onSeeAll and lines up whether or not the
    // row overflows.
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget row({required Key key, required int itemCount}) => CoverRowSection(
      key: key,
      title: 'Row',
      onSeeAll: () {},
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 120,
      itemCount: itemCount,
      itemBuilder: (context, index) =>
          SizedBox(width: 100, height: 120, child: Text('Item $index')),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              row(key: const Key('overflow'), itemCount: 20),
              row(key: const Key('short'), itemCount: 3),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final overflowSeeAll = tester.getTopRight(
      find.descendant(
        of: find.byKey(const Key('overflow')),
        matching: find.text('See all'),
      ),
    );
    final shortSeeAll = tester.getTopRight(
      find.descendant(
        of: find.byKey(const Key('short')),
        matching: find.text('See all'),
      ),
    );
    expect(shortSeeAll.dx, overflowSeeAll.dx);
    expect(
      find.descendant(
        of: find.byKey(const Key('short')),
        matching: find.byTooltip('Next'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('overflow')),
        matching: find.byTooltip('Next'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('overflow')),
        matching: find.text('See all'),
      ),
    );
  });
}
