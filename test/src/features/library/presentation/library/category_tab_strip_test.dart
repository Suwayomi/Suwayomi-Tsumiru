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
  required void Function(TabController controller) onController,
}) async {
  // Drive the strip width through the view: it fills the Scaffold body, so
  // LayoutBuilder measures the real width under test.
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DefaultTabController(
          length: tabs.length,
          initialIndex: 0,
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

List<StripTab> _tabs(List<String> names) => [
  for (final name in names) (name: name, count: null),
];

void main() {
  group('CategoryTabStrip', () {
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
  });
}
