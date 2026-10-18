// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumiru/src/features/library/presentation/library/widgets/category_tab_strip.dart';
import 'package:tsumiru/src/l10n/generated/app_localizations.dart';

Future<void> _pumpStrip(
  WidgetTester tester,
  List<StripTab> tabs, {
  double width = 1400,
  int initialIndex = 0,
  Locale? locale,
  required void Function(TabController controller) onController,
}) async {
  // Drive the strip width through the view: it fills the Scaffold body, so
  // LayoutBuilder measures the real width under test.
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DefaultTabController(
          length: tabs.length,
          initialIndex: initialIndex,
          child: Builder(
            builder: (context) {
              onController(DefaultTabController.of(context));
              return CategoryTabStrip(tabs: tabs);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Names currently rendered in the strip row (More label excluded by using
/// exact tab-name matches while the menu is closed).
Set<String> _visibleNames(WidgetTester tester, List<StripTab> tabs) => {
  for (final tab in tabs)
    if (find.text(tab.name, findRichText: true).evaluate().isNotEmpty) tab.name,
};

List<StripTab> _tabs(List<String> names) => [
  for (final name in names) (name: name, count: null),
];

void main() {
  group('CategoryTabStrip', () {
    testWidgets('3 short categories show all, no More', (tester) async {
      late TabController controller;
      await _pumpStrip(
        tester,
        _tabs(['Alpha', 'Beta', 'Gamma']),
        onController: (c) => controller = c,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Alpha', findRichText: true), findsOneWidget);
      expect(find.text('Beta', findRichText: true), findsOneWidget);
      expect(find.text('Gamma', findRichText: true), findsOneWidget);
      expect(find.textContaining('More (', findRichText: true), findsNothing);
      expect(controller.index, 0);
    });

    testWidgets('12 categories at 1000 px overflow into More (N)', (
      tester,
    ) async {
      late TabController controller;
      final tabs = _tabs([for (var i = 0; i < 12; i++) 'Category $i']);
      await _pumpStrip(
        tester,
        tabs,
        width: 1000,
        onController: (c) => controller = c,
      );

      expect(tester.takeException(), isNull);
      final more = find.textContaining('More (', findRichText: true);
      expect(more, findsOneWidget);
      final label = tester.widget<RichText>(more).text.toPlainText();
      final hiddenCount = int.parse(
        RegExp(r'More \((\d+)\)').firstMatch(label)!.group(1)!,
      );
      expect(hiddenCount, greaterThan(0));
      expect(controller.index, 0);

      // Visible tabs + hidden == all tabs (hidden tabs have no widget,
      // so this runs while the menu is closed).
      var visible = 0;
      for (var i = 0; i < tabs.length; i++) {
        if (find.text(tabs[i].name, findRichText: true).evaluate().isNotEmpty) {
          visible++;
        }
      }
      expect(visible + hiddenCount, 12);

      // The menu lists exactly the hidden categories; picking the first
      // hidden one selects it.
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(hiddenCount));
      await tester.tap(find.byType(MenuItemButton).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.index, 12 - hiddenCount);
    });

    testWidgets('picking a hidden category selects it; row unchanged', (
      tester,
    ) async {
      late TabController controller;
      final tabs = _tabs([
        'A',
        'B',
        'C',
        for (var i = 3; i < 12; i++) 'Long category name $i',
      ]);
      await _pumpStrip(
        tester,
        tabs,
        width: 1000,
        onController: (c) => controller = c,
      );

      expect(find.text('A', findRichText: true), findsOneWidget);
      expect(find.text('B', findRichText: true), findsOneWidget);
      expect(find.text('C', findRichText: true), findsOneWidget);

      await tester.tap(find.textContaining('More (', findRichText: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Long category name 11', findRichText: true));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(controller.index, 11);
      // The visible row never reshuffles.
      expect(find.text('A', findRichText: true), findsOneWidget);
      expect(find.text('B', findRichText: true), findsOneWidget);
      expect(find.text('C', findRichText: true), findsOneWidget);
      // More now shows the hidden selection instead of the count.
      expect(find.textContaining('More (', findRichText: true), findsNothing);
      expect(
        find.text('Long category name 11', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets(
      'selecting a very long hidden name leaves visible tabs identical',
      (tester) async {
        const longName =
            'An Extremely Long Category Name That Goes On And On And On Forever';
        late TabController controller;
        final tabs = _tabs([
          for (var i = 0; i < 11; i++) 'Category $i',
          longName,
        ]);
        await _pumpStrip(
          tester,
          tabs,
          width: 1000,
          onController: (c) => controller = c,
        );

        expect(tester.takeException(), isNull);
        // The long name starts hidden behind the count label.
        expect(find.text(longName, findRichText: true), findsNothing);
        expect(
          find.textContaining('More (', findRichText: true),
          findsOneWidget,
        );
        final before = _visibleNames(tester, tabs);
        expect(before, isNotEmpty);
        expect(before, isNot(contains(longName)));

        await tester.tap(find.textContaining('More (', findRichText: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text(longName, findRichText: true).last);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(controller.index, 11);
        // The row never reshuffles: the same tabs stay visible, and the long
        // name appears only in the More control, ellipsized with a tooltip.
        final after = _visibleNames(tester, tabs)..remove(longName);
        expect(after, before);
        expect(find.textContaining('More (', findRichText: true), findsNothing);
        expect(find.byTooltip(longName), findsOneWidget);
      },
    );

    testWidgets('More label comes from l10n', (tester) async {
      late TabController controller;
      final tabs = _tabs([for (var i = 0; i < 12; i++) 'Kategorie $i']);
      await _pumpStrip(
        tester,
        tabs,
        width: 1000,
        locale: const Locale('de'),
        onController: (c) => controller = c,
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Mehr (', findRichText: true), findsOneWidget);
      expect(find.textContaining('More (', findRichText: true), findsNothing);
      expect(controller.index, 0);
    });

    testWidgets('long German names do not clip', (tester) async {
      late TabController controller;
      await _pumpStrip(
        tester,
        _tabs([
          'Standard',
          'Abgeschlossene Serien',
          'Noch nicht begonnene Titel',
          'Lesezeichen und Favoriten',
          'Ungelesene Kapitel vorhanden',
        ]),
        width: 1000,
        onController: (c) => controller = c,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Standard', findRichText: true), findsOneWidget);
      expect(controller.index, 0);
    });

    testWidgets('counts render muted next to the name', (tester) async {
      late TabController controller;
      await _pumpStrip(tester, const [
        (name: 'Alpha', count: 12),
        (name: 'Beta', count: 3),
      ], onController: (c) => controller = c);

      expect(tester.takeException(), isNull);
      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.textSpan!.toPlainText());
      expect(labels, contains('Alpha (12)'));
      expect(labels, contains('Beta (3)'));
      expect(controller.index, 0);
    });
  });
}
