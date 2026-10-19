// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.controller!.offset, greaterThan(0));
  });

  testWidgets('a row that fits shows no arrows and no fade', (tester) async {
    await _pump(tester, size: const Size(1000, 600), itemCount: 3);

    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(
      tester.widget<CoverRowEdgeFade>(find.byType(CoverRowEdgeFade)).fade,
      isFalse,
    );
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

  testWidgets('See all lines up whether or not the row overflows', (
    tester,
  ) async {
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

    final short = find.byKey(const Key('short'));
    expect(
      find.descendant(of: short, matching: find.byTooltip('Back')),
      findsNothing,
    );
    expect(
      find.descendant(of: short, matching: find.byTooltip('Next')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('overflow')),
        matching: find.byTooltip('Next'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a header-less row shows arrows only while it overflows', (
    tester,
  ) async {
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

    await pump(3);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byTooltip('Next'), findsNothing);

    await pump(20);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Next'), findsOneWidget);

    final sectionTop = tester.getTopLeft(find.byType(CoverRowSection)).dy;
    final arrowsTop = tester.getTopLeft(find.byTooltip('Next')).dy;
    final listTop = tester.getTopLeft(find.byType(ListView).first).dy;
    expect(arrowsTop, greaterThanOrEqualTo(sectionTop));
    expect(arrowsTop, lessThan(listTop));
  });

  testWidgets('a titled row keeps its offset when it reaches the end', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1000, 600), itemCount: 20);

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    final position = list.controller!.position;
    expect(position.pixels, position.maxScrollExtent);
    expect(
      tester.widget<CoverRowEdgeFade>(find.byType(CoverRowEdgeFade)).fade,
      isFalse,
    );
  });

  testWidgets('a header-less row keeps its offset when it reaches the end', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CoverRowSection(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            height: 120,
            itemCount: 20,
            itemBuilder: (context, index) =>
                SizedBox(width: 100, height: 120, child: Text('Item $index')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    final position = list.controller!.position;
    expect(position.pixels, position.maxScrollExtent);
    expect(
      tester.widget<CoverRowEdgeFade>(find.byType(CoverRowEdgeFade)).fade,
      isFalse,
    );
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

  testWidgets('the edge fade leaves no bright column at a fractional width', (
    tester,
  ) async {
    for (final dpr in [1.25, 1.5]) {
      tester.view.physicalSize = const Size(600, 200);
      tester.view.devicePixelRatio = dpr;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 333.5,
                height: 100,
                child: CoverRowEdgeFade(
                  fade: true,
                  color: Colors.white,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: dpr),
      ))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      int alphaAt(int x, int y) =>
          bytes.getUint8((y * image.width + x) * 4 + 3);
      final y = image.height ~/ 2;
      final last = image.width - 1;
      expect(alphaAt(last, y), lessThan(8), reason: 'dpr $dpr');
      expect(
        alphaAt(last, y),
        lessThanOrEqualTo(alphaAt(last - 3, y)),
        reason: 'dpr $dpr',
      );
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  test('the fade reaches transparent before the right edge', () {
    final stops = CoverRowEdgeFade.stopsFor(333.5);
    expect(stops.last, lessThan(1));
    expect(stops.last, closeTo(1 - 2 / 333.5, 1e-9));
  });
}
